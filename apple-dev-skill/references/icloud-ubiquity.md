# iCloud Ubiquity Container

File download, discovery, and restore patterns for apps using iCloud Documents (`CloudDocuments` entitlement) via `FileManager.url(forUbiquityContainerIdentifier:)`.

> For the provider-agnostic backup architecture (OAuth scope/403 re-consent, atomic pointer publish, storage-location migration, restore-integrity hardening) and the same user-visible-storage principle applied to Google Drive / Dropbox, see [cloud-backup-providers](cloud-backup-providers.md).

## Core Concepts

| Concept | Implication |
|---------|-------------|
| Files are **lazily materialized** | Local filesystem may be empty even when iCloud has data |
| `startDownloadingUbiquitousItem(at:)` is a **hint** | It asks the daemon to download; completion is asynchronous and not guaranteed |
| The iCloud daemon (`bird`) controls scheduling | You cannot force immediate transfer; network, power, quota, and system state affect timing |
| `NSMetadataQuery` is the **source of truth** for remote files | `FileManager.fileExists` / directory enumeration only sees locally materialized files |

## Discovery: NSMetadataQuery

Use `NSMetadataQuery` to find files that exist in iCloud but haven't synced locally yet. **Critical on fresh install / new device** where the local ubiquity container is empty.

### Must Run on Main Actor

`NSMetadataQuery` requires a thread with an active run loop. In Swift concurrency, `async` functions run on the cooperative thread pool — **no run loop**.

```swift
// ✅ Correct: pinned to @MainActor
@MainActor
final class ICloudFolderDiscovery {
    func discover() async -> [String] {
        await withCheckedContinuation { continuation in
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(
                format: "%K == %@",
                NSMetadataItemFSNameKey, "metadata.json"
            )
            // observe NSMetadataQueryDidFinishGathering, then query.start()
            ...
        }
    }
}
```

```swift
// ❌ Wrong: async function on cooperative pool — query silently returns nothing
func discover() async -> [String] {
    let query = NSMetadataQuery()
    query.start() // no run loop → never gathers results
}
```

**Trap**: Same-device testing masks this bug because local filesystem cache already has the files. The `NSMetadataQuery` fallback path only triggers on a fresh install.

## Downloading Files

### Single File

```swift
try FileManager.default.startDownloadingUbiquitousItem(at: url)
// Then poll or observe ubiquitousItemDownloadingStatusKey
```

### Bulk Download — Batch Request + Progress-Based Timeout

For restoring backups with hundreds of files:

| Strategy | Why |
|----------|-----|
| Request all downloads upfront | `startDownloadingUbiquitousItem` is a lightweight hint; let the daemon see the full scope |
| Poll `ubiquitousItemDownloadingStatusKey` collectively | Check all files every 2–3 seconds |
| **Progress-based timeout, not fixed deadline** | As long as ≥1 file completes per window, keep waiting; only fail after prolonged stall |
| Re-request stuck files on stall | `startDownloadingUbiquitousItem` again for files that haven't progressed |
| Check `ubiquitousItemDownloadingErrorKey` | Detect per-file iCloud errors (quota, server, auth) immediately instead of waiting for stall |

### Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Fixed 60-second timeout per file | 436 images × slow connection = guaranteed failure | Progress-based stall detection; no global deadline |
| Sequential download (file-by-file, wait for each) | Prevents daemon from batching; total time = Σ per-file | Batch request all, poll collectively |
| `try?` on all `startDownloadingUbiquitousItem` calls | Swallows container-unavailable / quota errors | Use `try`; fail fast if ALL requests fail |
| Polling without checking `ubiquitousItemDownloadingErrorKey` | iCloud reports failure but app waits until timeout | Check error key each poll; abort if all remaining files have errors |
| Treating `.downloaded` as restore-success | Silently restores a **stale** backup on cross-device restore — a newer version on iCloud was never fetched | Only accept `.current`; keep polling until daemon confirms latest version |

### Poll With a FRESH URL Every Iteration

**`URL` caches resource values per instance.** A polling loop that re-queries
the same `URL` instances re-reads the first answer forever —
`isUploaded` / `downloadingStatus` never flips even after the daemon
finishes, so the wait burns its whole budget and times out. Rebuild the URL
from its path on every poll:

```swift
while Date() < deadline {
    for staleURL in urls {
        let url = URL(fileURLWithPath: staleURL.path)   // fresh instance = fresh values
        let values = try url.resourceValues(forKeys: keys)
        ...
    }
    try await Task.sleep(for: .seconds(2))
}
```

This applies to **both directions** (upload confirmation and download
status). It is the same reason `NSMetadataQuery` — not repeated
`resourceValues` reads — is the source of truth for remote state.

### URL Resource Keys for Download Status

```swift
let keys: Set<URLResourceKey> = [
    .ubiquitousItemDownloadingStatusKey,  // .current / .downloaded / .notDownloaded
    .ubiquitousItemDownloadingErrorKey,   // NSError? — nil if no error
    .ubiquitousItemIsDownloadingKey,      // Bool — actively transferring
]
let values = try url.resourceValues(forKeys: keys)
```

- `.current` = fully downloaded and up-to-date
- `.downloaded` = local copy exists but **may be stale** — another device uploaded a newer version that hasn't synced yet
- `.notDownloaded` = only a placeholder (`.filename.icloud`) exists locally

**Restore-success rule**: only `.current` is safe to accept. Restoring on `.downloaded` is the classic cross-device data-loss bug — user backs up from phone A, restores on phone B which still has yesterday's local copy, app cheerfully overwrites with the older snapshot. Always poll until `.current`, or fail with a clear stall error.

### Evicted File Placeholders

iCloud creates `.originalName.icloud` placeholder files for evicted content. When enumerating files:

```swift
// Resolve placeholder to real URL
if name.hasPrefix("."), name.hasSuffix(".icloud") {
    let realName = String(name.dropFirst().dropLast(7))
    let realURL = parent.appendingPathComponent(realName)
    // Use realURL for startDownloadingUbiquitousItem
}
```

## Uploading Files (Backup Direction)

Writing into the ubiquity container is a **local copy** — the daemon uploads
asynchronously afterwards. A correct upload wait has four properties:

| Property | Rule | Why |
|----------|------|-----|
| Progress source | Report per-file progress from the **upload-confirmation poll** (`ubiquitousItemIsUploadedKey` count), never from the local copy loop | Local copies finish in milliseconds; reporting them pins the UI at "N/N" for the entire real upload |
| Liveness, not just deadline | Fail fast when nothing transitioned to uploaded AND nothing reports `ubiquitousItemIsUploadingKey` for a stall window (~3 min) | A wedged daemon (signed-out account, quota, brctl faults) otherwise burns the full budget — 120s × 20 files ≈ 40 silent minutes — before the user sees an error. `isUploading == true` resets the stall clock: a slow single large file is alive, not stalled |
| Budget floor | `max(perFileTimeout × count, ~300s)` | A 1-file wait (the `CURRENT.json` pointer commit) must outlive one slow-but-alive daemon cycle and must not be tighter than the stall detector it defers to |
| Failure diagnostics | On stall/timeout, dump each not-uploaded file's `isUploaded`/`isUploading` | Device logs then name the exact file the daemon is sitting on |

```swift
var lastUploadedCount = -1
var lastActivity = Date()
while Date() < deadline {
    var uploadedCount = 0, anyUploading = false
    for staleURL in urls {
        let url = URL(fileURLWithPath: staleURL.path)          // fresh instance!
        let v = try url.resourceValues(forKeys: keys)
        if let error = v.ubiquitousItemUploadingError { throw ... }  // quota/auth — don't wait it out
        if v.ubiquitousItemIsUploaded == true { uploadedCount += 1 }
        else if v.ubiquitousItemIsUploading == true { anyUploading = true }
    }
    if uploadedCount == urls.count { return }
    if uploadedCount != lastUploadedCount {                    // real progress → report + reset stall
        progress(uploadedCount, urls.count)
        lastUploadedCount = uploadedCount; lastActivity = Date()
    } else if anyUploading {
        lastActivity = Date()                                  // alive, keep waiting
    } else if Date().timeIntervalSince(lastActivity) > stallTimeout {
        throw ...("iCloud is not syncing — check iCloud storage and iCloud Drive settings")
    }
    try await Task.sleep(for: .seconds(2))
}
```

Gate the pointer commit (`CURRENT.json`) on the bundle wait completing — see
atomic publish in [cloud-backup-providers](cloud-backup-providers.md).

## NSUbiquitousContainers — Files App Visibility

By default, an app's iCloud ubiquity container is **invisible** in the Files app. Add `NSUbiquitousContainers` to `Info.plist` to expose it:

```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.example.MyApp</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>MyApp</string>
        <key>NSUbiquitousContainerSupportedFolderLevels</key>
        <string>Any</string>
    </dict>
</dict>
```

**Tuist `Project.swift`** — use `Plist.Value` literals, no `as [String: Any]` cast:

```swift
"NSUbiquitousContainers": [
    "iCloud.com.example.MyApp": [
        "NSUbiquitousContainerIsDocumentScopePublic": true,
        "NSUbiquitousContainerSupportedFolderLevels": "Any",
        "NSUbiquitousContainerName": "MyApp",
    ],
],
```

### Requirements

- App must have `com.apple.developer.icloud-container-identifiers` entitlement with matching container ID
- Container ID in plist must match entitlement exactly
- **`FileManager.url(forUbiquityContainerIdentifier:)` must have been called at least once** — this is what actually creates the container on iCloud's servers; the plist only declares visibility intent
- **The `Documents/` directory must exist** — an empty or non-existent directory means nothing to show in Files app

### Trap: Plist Alone Does Not Create the Container

`NSUbiquitousContainers` tells Files app "this container is allowed to be visible." But the container directory won't appear in iCloud Drive until **both** conditions are met:

1. `FileManager.url(forUbiquityContainerIdentifier:)` has been called → creates the container on iCloud's servers
2. The `Documents/` subdirectory exists on disk

If the app only calls `url(forUbiquityContainerIdentifier:)` lazily (e.g. during backup), users who never back up will never see the folder. **Fix**: eagerly touch the container at app startup.

```swift
// Call at DI init / app launch — cheap and idempotent
func ensureContainerExists() {
    guard FileManager.default.ubiquityIdentityToken != nil else { return }
    guard let container = FileManager.default.url(
        forUbiquityContainerIdentifier: containerID
    ) else { return }
    let docs = container.appendingPathComponent("Documents")
    try? FileManager.default.createDirectory(
        at: docs, withIntermediateDirectories: true
    )
}
```

This works for both fresh installs and app updates — iOS re-reads Info.plist on every install/update, and the eager init ensures the container is ready.

### Behavior

- Folder appears in Files app → iCloud Drive after app update (no fresh install required)
- Appearance may be delayed until iCloud re-indexes the container; pull-to-refresh in Files helps
- **Users can delete, rename, or move files** — treat the Documents directory as user-owned
- Useful as a recovery path: users can manually trigger iCloud sync by opening the folder in Files

### When to Use

| Scenario | Recommendation |
|----------|---------------|
| App stores user-facing documents (notes, exports) | ✅ Use — expected document behavior |
| App stores backup archives the user may need to access | ✅ Use — provides recovery path on restore failure |
| App stores internal databases or app-private state | ❌ Don't expose — risk of user corruption |

## Fresh Install Restore Checklist

On a new device or after app reinstall, the entire ubiquity container may be empty locally:

1. **Don't trust `FileManager.fileExists`** — use `NSMetadataQuery` to discover remote files
2. **NSMetadataQuery must be `@MainActor`** — cooperative thread pool has no run loop
3. **`startDownloadingUbiquitousItem` may take minutes** — show "syncing" UI, not a progress bar
4. **Use progress-based timeout** — stall detection, not fixed deadline
5. **Check `ubiquitousItemDownloadingErrorKey`** — detect quota/server/auth failures early
6. **Provider-specific UI** — don't show "Syncing from iCloud…" for Dropbox/Google Drive restores
7. **Log `NSError` domain + code** — iCloud errors are not exhaustively documented; preserve the full error for diagnostics
