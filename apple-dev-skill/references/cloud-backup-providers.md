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
> provider.

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
    throw BackupError.providerNotAuthorized
}
```

- Declare the multi-scope string up front:
  `"…/auth/drive.appdata …/auth/drive.file"` (space-separated). Keep the old
  scope if you still need to read pre-migration data.
- Put the 403 check in the **one** response validator every request funnels
  through, so no call site can bypass it.
- Make `providerNotAuthorized` route to the same "Reconnect" UI as a first-time
  connect — re-consent and connect are the same flow.

## Transfer Session: Ephemeral + URLCache Fully Disabled

Give backup/restore transfers a dedicated `URLSession` with the cache OFF:

```swift
enum BackupURLSession {
  static let shared: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 120
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    return URLSession(configuration: config)
  }()
}
```

- **URLCache must be disabled for POST-download APIs.** CFNetwork caches
  POST responses keyed by URL (Dropbox `files/download` style endpoints),
  and replaying a cached POST deterministically kills the connection
  mid-body — `-1005 networkConnectionLost`, errno 57 — even on a
  freshly-opened connection. Signature: the FIRST fetch of a URL succeeds,
  every repeat fails, retries included; the failing task summary shows
  `cache_hit=true`. Transfers gain nothing from HTTP caching anyway: blobs
  are written to disk and manifests/pointers must be fresh.
- **Ephemeral** because transfers need no persistent cookies/credentials,
  and it sidesteps shared-pool interference from the rest of the app.
- Set both `urlCache = nil` AND the ignore policy — either alone fixes the
  replay bug, both makes the intent unmissable.

### POSTs Are Not Auto-Retried — Add a Bounded Retry

URLSession transparently retries **idempotent GETs** on a stale keep-alive /
reset connection; **POSTs surface the error to you**. REST content APIs that
download via POST (Dropbox) therefore need one explicit bounded retry on
`URLError.networkConnectionLost`; GET-based providers (Google Drive
`?alt=media`) get the same resilience for free:

```swift
do {
  (data, response) = try await makeRequest(token)
} catch let urlError as URLError where urlError.code == .networkConnectionLost {
  try await Task.sleep(for: .milliseconds(300))   // stale-connection reuse
  (data, response) = try await makeRequest(token)
}
```

If the retry ALSO fails deterministically, stop retrying and split the
problem: replay the exact request with `curl` and the same bearer token. curl
OK + app failing = client-side (session config, cache, request shape); curl
failing = server/account/network. One experiment, whole diagnosis space
halved. The CFNetwork task-summary log line is the other high-signal probe:
`response_status`, `cache_hit`, `reused`, `protocol` tell you whether the
server answered, the cache interfered, and the connection was fresh.

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

## Breaking Bundle Formats: New Pointer Namespace, Never the Old Pointer

**The pointer file is read by every reader ever shipped.** A schema gate in
today's build cannot protect yesterday's builds — they blindly restore
whatever `CURRENT.json` names, then fail at decode time (or worse, after the
DB swap). So the moment a bundle format needs a newer reader, route it to a
NEW pointer file and freeze the old one's contract:

| Rule | Why |
|------|-----|
| `CURRENT.json` may only ever reference bundles the OLDEST shipped reader can consume | Legacy readers have no gate; stale-but-readable beats newest-but-crashing |
| Bundles requiring reader schema N ≥ 2 commit to their own namespace (`CURRENT2.json`, …) | Old readers never see the name; updated readers opt in |
| Updated readers resolve the **newest version across all namespaces** | Fixed-width UTC-timestamp versionIds compare lexicographically, so "newest" is a string max — handles a v1 backup made from an old device AFTER a v2 backup from a new one |
| Cleanup keep-sets and pending-version listings treat EVERY namespace target as committed | After a schema-2 commit, `CURRENT.json` still references an older schema-1 bundle; pruning it leaves legacy readers dangling |
| Keep the in-app schema gate too (reject `schemaVersion > supported` before any download) | Defense in depth for FUTURE formats: a schema-3 writer will use `CURRENT3.json`, but the gate also covers tampered or hand-moved bundles |

Write rule stays minimum-reader: a bundle that doesn't use the new feature
writes the old schema AND commits to the old pointer — users who never touch
the feature keep full cross-version compatibility.

Shape it as one primitive + shared derivation so all providers stay in sync:

```swift
protocol BackupProvider {
    func fetchPointer(minimumReaderSchema: Int) async throws -> BackupCurrentPointer?
    func commitCurrentPointer(version: String, minimumReaderSchema: Int) async throws
}
extension BackupProvider {
    func fetchCurrentPointer() async throws -> BackupCurrentPointer? { /* max across namespaces */ }
    func committedVersions() async -> Set<String> { /* every namespace target */ }
}
```

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
| **Close the live DB connections BEFORE swapping the sqlite file**, rebuild after | Replacing the file under open connections is a SQLite API violation (`BUG IN CLIENT OF libsqlite3.dylib: vnode unlinked while in use`): old handles keep reading the dead inode and any write through them can corrupt or silently diverge. Give the DB manager an explicit close/reopen lifecycle for restore, and notify long-lived readers (observers, repositories) to re-resolve. |

```swift
// Path-traversal guard before any download/swap:
for name in manifest.mediaFilenames {
    guard name == (name as NSString).lastPathComponent, !name.contains("/") else {
        throw BackupError.restoreFailed("Illegal media filename in manifest: \(name)")
    }
}
```

## Remote Snapshot Status: Authority, Revalidation, Cache

A backup screen must answer "what would Restore give me?" from live
cloud state, not from device-local last-backup records (those only say
what THIS device last did — another device may have overwritten or
deleted the cloud copy). Model it as an explicit per-provider status:
`unknown / checking / none / unreachable / found(info)`.

### Listing authority is a per-provider trait

Not every provider's `list` means the same thing. Gate any
definitive-sounding decision on it:

| Provider list | Meaning of an empty listing | May disable Restore on "none"? |
|---|---|---|
| REST enumeration (Drive, Dropbox) | The backup truly doesn't exist | Yes |
| Local mirror (iCloud ubiquity dir via FileManager) | "Not detected locally" — may lag sync or not be materialized | No — keep Restore enabled, use non-assertive copy ("not detected"), let the download's own not-found error be the backstop |

Expose it as a protocol trait (`var listIsAuthoritative: Bool`, default
`true`, local-mirror stores override `false`) so the UI never switches
on concrete provider types.

### Stale-while-revalidate, never downgrade

A refresh that re-lists while a `.found` is already known must keep
showing it — the loading state is only honest when there is nothing to
show. Downgrading known results to "checking" makes every screen
re-entry flash a loading state over data the app already has.

### Display cache: event-driven invalidation, not TTL

Persist the last APPLIED `.found` info per provider (JSON in a KV
store) and seed the status from it at mount, so relaunch / re-entry
shows the last-known snapshot immediately. Freshness comes from
revalidate-on-appearance, so the cache needs no expiry — it is
invalidated by events that actually change the answer:

- new applied `.found` → overwrite
- **authoritative** listing confirms empty → clear
- non-authoritative listing comes back empty (local mirror lag) → keep
  cache AND keep a known `.found` — "not detected locally" must not
  destroy durable knowledge over a transient mirror state
- disconnect → clear
- listing failure (`unreachable`) → keep (stale info beats nothing while
  offline; the visible status still reports unreachable honestly)

The cache is display-only — restore correctness must never read it.

### Bounding and racing the refresh

- **Coalesce, don't cache**: a short window (~10s) that absorbs rapid
  re-entry bursts, plus in-flight dedupe (one listing per provider at a
  time). Anything longer delays external-deletion detection.
- **Actor reentrancy**: every `await` inside the refresh is a point
  where disconnect / auth flip / backup / restore can interleave. Guard
  writes with a per-provider generation token bumped by those events; a
  refresh whose token no longer matches discards its result — otherwise
  a slow listing resurrects `.found` on credentials the user just
  disconnected.
- **Stamp the coalescing window only when a result is applied** (never
  in `defer`): a discarded stale refresh that stamps the window
  suppresses the next legitimate refresh after the event that
  invalidated it.

## Advisory Contents Manifest (Flat-Overwrite Layouts)

Listing metadata gives date + size but not *contents*. To let the UI
answer "what's in this backup?" (counts, authoring device) before a
restore, upload a small `manifest.json` beside the snapshot. Rules that
keep it honest:

| Rule | Why |
|------|-----|
| Upload the manifest **last** (data → media → manifest) | Same principle as pointer-last atomic publish: a reader must never see a manifest describing an upload that hasn't finished |
| Compute counts from the **uploaded artifact** (the checkpointed snapshot file), never the live store | The live store keeps taking writes during the upload; live counts describe data a restore cannot return. Open the snapshot copy and count there |
| Manifest failure never fails the backup | It's advisory display data; the snapshot is the durable outcome |
| A backup that lands no manifest — unproducible OR upload failed — **deletes** the remote one (best-effort) | A stale manifest describing a newer snapshot lies; absent beats wrong. The delete must cover the upload-failure path too, not just "never tried" |
| Readers treat missing / corrupt / future-`schemaVersion` manifests as absent | Display degrades to metadata-only; the manifest must never gate restore or surface an error |
| Carry `schemaVersion` from day one | Future breaking manifest changes get a version gate without a new filename |
