# Cloud Backup Providers (OAuth REST)

Correct patterns for app-side cloud backup/restore against OAuth REST providers
(Google Drive, Dropbox) and, by analogy, iCloud. These are the *intended*
designs to copy into a new project — not a debugging log.

For the iCloud-specific transport (ubiquity container, `NSMetadataQuery`,
download status), see [icloud-ubiquity](icloud-ubiquity.md). This file covers
the provider-agnostic architecture and the OAuth/REST specifics.

## Iron Law: Store Backups Where the User Can See Them

**Default to user-visible storage. Hidden app-private spaces are an
anti-pattern for anything the user may need to recover.**

| Provider | ✅ User-visible (default) | ❌ Hidden app space |
|----------|--------------------------|---------------------|
| Google Drive | `drive.file` scope → `My Drive/<App>/` folder | `drive.appdata` → `appDataFolder` |
| Dropbox | App-folder (`Apps/<App>/`, visible in the user's Dropbox) | — |
| iCloud | `NSUbiquitousContainers` → Files app `Documents/` | private container (invisible in Files) |

Why visible wins, every time:

- **Recovery path** — when restore fails or the user switches platforms, they
  can still see and copy their data manually. Hidden data is a black box.
- **Trust** — users distrust an app that writes to cloud storage they can't
  inspect. Visible folders make the contract honest.
- **Survives uninstall** — data the user can find is data they can keep.

Treat the visible folder as **user-owned**: they may rename, move, or delete
files. Backup/restore must tolerate a missing or reorganized folder
(find-or-create, never assume).

> This is the same principle as `NSUbiquitousContainerIsDocumentScopePublic`
> in [icloud-ubiquity](icloud-ubiquity.md) — apply it uniformly across every
> provider. New cloud-sync features should adopt visible storage from day one.

### Find-or-Create the Visible Root, Cache the Id

All bundle operations hang off one find-or-create root folder. Cache its id
(backups are serialised, so a non-atomic cache is safe):

```swift
func rootFolderId() async throws -> String {
    if let cached = cachedRootFolderId { return cached }
    let folderMime = "application/vnd.google-apps.folder"
    // Reuse an existing visible folder if present...
    if let existing = try await findChild(name: visibleRootName, parentId: "root"),
       existing.mimeType == folderMime {
        cachedRootFolderId = existing.id
        return existing.id
    }
    // ...otherwise create it under "root" (My Drive).
    let metadata: [String: Any] = [
        "name": visibleRootName,
        "mimeType": folderMime,
        "parents": ["root"],
    ]
    // POST drive/v3/files → read back the new id
    ...
    cachedRootFolderId = id
    return id
}
```

`files.list` queries must pass `spaces=drive` (not `appDataFolder`) once you
move to the visible folder. Keep `space` a parameter so the migration path can
still read the old hidden space.

## OAuth Scope Expansion → Force Re-Consent

**Adding a scope does NOT retroactively grant it to an existing refresh token.
A token refresh returns the OLD scope set.**

Symptom: an already-"connected" user gets **403** with `insufficientScopes` in
the body the moment your code touches the newly-scoped resource (e.g. you added
`drive.file` but the cached token only has `drive.appdata`).

Fix: detect the 403, wipe **both** access and refresh tokens, and surface it as
"not authorized" so the UI re-runs the **full consent** flow (which re-grants
all current scopes). A plain refresh will not.

```swift
// In the shared HTTP-response validator, before the generic 2xx check:
let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
if http.statusCode == 403, body.contains("insufficientScopes") {
    tokenStore.delete(forKey: keychainAccessToken)
    tokenStore.delete(forKey: keychainRefreshToken)   // refresh keeps old scopes — must drop it too
    throw SottoError.providerNotAuthorized
}
```

- Declare the multi-scope string up front:
  `"…/auth/drive.appdata …/auth/drive.file"` (space-separated). Keep the old
  scope if you still need to read pre-migration data.
- Put the 403 check in the **one** response validator every request funnels
  through, so no call site can bypass it.
- Make `providerNotAuthorized` route to the same "Reconnect" UI as a first-time
  connect — re-consent and connect are the same flow.

## URLSession Upload Task: Body Goes via `from:`, Not `httpBody`

When using `URLSession.upload(for:from:)`, the body MUST come from the `from:`
parameter **only**. Also setting `request.httpBody` makes URLSession reject the
task:

> "request should not contain a body or a body stream"

```swift
var request = URLRequest(url: url)
request.httpMethod = "PATCH"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
// request.httpBody = body            // ❌ rejected when paired with upload(for:from:)
return try await session.upload(for: request, from: body)   // ✅ body via from:
```

Use `data(for:)` when the body is already on the request; use
`upload(for:from:)` when you pass the body separately — never mix the two.

## Atomic Publish: Commit the Pointer Last

A versioned backup writes many files (DB snapshot, media, manifest) under
`backups/<versionId>/`. Publish atomically with a **single live pointer**
(`CURRENT.json`) that names the current version:

1. Write the full bundle into `backups/<versionId>/` (data + media + manifest).
2. **Last**, write/replace `CURRENT.json` to point at `<versionId>`.

A reader resolving `CURRENT.json` therefore always sees a *complete* version —
the old one until the pointer flips, the new one after. It can never observe a
half-written bundle. The same rule governs the migration copy below: copy every
file across, then commit the visible pointer last.

`versionId` is a UTC timestamp folder name (`yyyyMMdd'T'HHmmssSSS'Z'`). Use
**millisecond** precision — second precision lets two backups fired in the same
second mint the same id and overwrite a live version. The compact layout stays
lexicographically time-ordered, which resume and cleanup rely on.

## Storage-Location Migration Hook

When you change *where* a provider stores bundles (hidden → visible), add an
idempotent, best-effort migration hook. Default it to a no-op on the protocol so
other providers are unaffected:

```swift
protocol BackupProvider: Sendable {
    /// One-time migration when a provider changed where it stores bundles.
    /// Idempotent + best-effort; no-op by default.
    func migrateStorageLocationIfNeeded() async throws
}
extension BackupProvider {
    func migrateStorageLocationIfNeeded() async throws {}   // default no-op
}
```

Rules that make it safe:

| Rule | Why |
|------|-----|
| Run it on **restore**, not backup | A fresh backup already writes to the new location. An extra `await` before the backup snapshot would let a concurrent write slip ahead of the consistency gate. |
| Call it **best-effort** (`try?`) | Migration failure must never block the user; the new location works regardless. It only means an old cloud-only backup isn't carried forward. |
| **Idempotent**: bail if the visible folder already has `CURRENT.json` | Migrated, or freshly backed up — either way nothing to do. |
| Commit the visible pointer **last** | A reader never sees a half-copied bundle as live (see Atomic Publish). |
| Leave the old hidden data **untouched** | Safety net — don't delete the source until you're certain the new location is authoritative. |

```swift
// In the restore path, before resolving the pointer:
try? await provider.migrateStorageLocationIfNeeded()
guard let pointer = try await provider.fetchCurrentPointer() else { ... }
```

## Progress & Completion Reflect Durable State

**The operation is "done" at the durable commit, not at a faked 1.0.**

- Report completion when `CURRENT.json` commits — that's when the backup is
  authoritative. Don't fabricate a `1.0` the pipeline never actually emits.
- Drive UI dismissal off an explicit **"operation finished"** signal, not a
  progress value. If phases top out at `0.9` (commit), a card waiting for `1.0`
  freezes at 90% forever. Emit `onProgressFinished()` on end (success *or*
  failure); deliver the outcome separately.
- **Guard late callbacks**: a progress callback that arrives after the state
  reached `.idle` must not resurrect progress (which re-pins the UI as
  "working").

```swift
progress: { [weak self] p in
    guard let self, case .backingUp = self.state else { return }  // never revive after idle
    self.state = .backingUp(progress: 0.6, phase: p.phase)
}
```

## Best-Effort Cleanup Must Never Block Completion

Reaping old/pending versions is housekeeping. The backup is already durable via
the committed pointer, so cleanup must never pin the UI.

- **Time-box it** (e.g. 15s). On a provider with many stale folders a full sweep
  can run long; cap it and reap the remainder on the next backup.
- Keep it on the **awaited path** (don't fire-and-forget into a detached task
  that races version create/delete) — just bounded by a timeout, so no second
  backup starts mid-cleanup.

```swift
state = .backingUp(progress: 0.95, phase: .cleanup)
try? await Self.withTimeLimit(seconds: 15) {
    try await provider.cleanupVersions(keep: [bundle.versionId])
}
state = .idle   // always reached — cleanup never blocks completion
```

## Restore Integrity Hardening

A backup bundle is **untrusted input** (it can be tampered with in the cloud, or
corrupted). Harden the restore swap:

| Guard | Reason |
|-------|--------|
| Validate every manifest media filename is a **plain basename** before download/swap | Reject path traversal (`../…`) from a tampered manifest writing outside the media dir. |
| Key resume-skip on **SHA-256**, not byte size | Same-size-different-content lets a committed version silently disagree with its manifest. Content hash is the only safe equality. |
| Hold the shared write **gate** around the restore DB/media swap | The swap must not interleave with live note/media writes. |
| Commit/swap the DB and media **atomically** | A reader (or a crash) must see all-old or all-new, never a mixed state. |

```swift
// Path-traversal guard before any download/swap:
for name in manifest.mediaFilenames {
    guard name == (name as NSString).lastPathComponent, !name.contains("/") else {
        throw SottoError.backupFailed("Illegal media filename in manifest: \(name)")
    }
}
```

## Checklist for a New Cloud-Sync Feature

1. **Visible storage from day one** — `drive.file` / Dropbox app-folder /
   `NSUbiquitousContainers`. Never start with a hidden app space.
2. **Find-or-create** the root folder; cache its id; treat it as user-owned.
3. Route **403 `insufficientScopes`** → wipe both tokens → full re-consent.
4. `upload(for:from:)` body via `from:` only — no `httpBody`.
5. **Atomic publish** — write the bundle, flip a single `CURRENT.json` last;
   millisecond-precision version ids.
6. Add an **idempotent best-effort migration hook** for any future location
   change; run it on restore; pointer last; leave old data as a safety net.
7. Progress/completion reflect **durable commit**; explicit finish signal;
   guard late callbacks.
8. **Time-box** cleanup; never block completion.
9. Treat the restore bundle as **untrusted**: basename guard, SHA-256 resume,
   write gate, atomic swap.
