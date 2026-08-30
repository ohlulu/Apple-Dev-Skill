# Build Phase Scripts

## Principles

1. **`set -euo pipefail`** at the top — fail on any error
2. **Check tool existence** before running — `command -v tool >/dev/null 2>&1`
3. **Fail loudly on critical path** — `exit 1` if binary not found
4. **Formatters belong in git hooks, not build phases** — see "Why not a build phase" below

## SwiftFormat (Pre-Commit Hook)

Do **not** put SwiftFormat in a build phase. Use a git pre-commit hook instead.

**Why not a build phase:**
- `xcodebuild archive` (Release config) formats the entire repo on disk, producing uncommitted diffs after every release
- Debug builds either skip formatting (wasted build phase) or format on every build (slow, noisy)
- Formatting should gate commits, not builds

**Hook: `scripts/hooks/pre-commit`**

```bash
#!/usr/bin/env bash
# Pre-commit hook — format only staged Swift files.
set -euo pipefail

STAGED=$(git diff --cached --diff-filter=d --name-only | grep '\.swift$' || true)

if [ -z "$STAGED" ]; then
  exit 0
fi

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "error: swiftformat not found (brew install swiftformat)" >&2
  exit 1
fi

echo "$STAGED" | while IFS= read -r file; do
  swiftformat "$file" 2>/dev/null
  git add "$file"
done
```

Key decisions:
- **Staged files only** — `git diff --cached` targets what's being committed, not the entire repo
- **Re-stage after format** — `git add` ensures the formatted version is what gets committed
- **`--diff-filter=d`** — skip deleted files
- **No build-time overhead** — zero impact on debug or archive builds

**⚠️ Pathspec commit caveat:** This hook calls `git add` to re-stage formatted files. If the caller uses `git commit -- <files>` (pathspec commit) instead of `git commit` (index commit), the re-staging is silently discarded — pathspec commit restores the index to its pre-commit snapshot after committing. Result: phantom staged+unstaged diffs that cancel each other out. Always use `git commit` (no pathspec) when a pre-commit hook calls `git add`.

**Wire up in Makefile `install` target:**

```makefile
install:
	@mkdir -p .git/hooks && ln -sf ../../scripts/hooks/pre-commit .git/hooks/pre-commit
	@echo "Installed git hooks."
	tuist generate
```

The symlink (`../../scripts/hooks/pre-commit`) is relative so it survives repo moves. Every developer gets the hook after `make install` (or `make` if `install` is the default goal).

## SwiftLint (Pre-Build)

```swift
.pre(
  script: """
  set -euo pipefail
  export PATH="$HOME/.mint/bin:$PATH"
  if ! command -v swiftlint >/dev/null 2>&1; then
  echo "warning: swiftlint not installed — skipping" >&2
  exit 0
  fi
  swiftlint --config "$SRCROOT/../.swiftlint.yml"
  """,
  name: "SwiftLint",
  basedOnDependencyAnalysis: false
),
```

Note: SwiftLint is often warning-level (exit 0 on missing), not error-level like SwiftFormat. Decide per project.

## Firebase Crashlytics dSYM Upload (Post-Build)

⚠️ SDK version changes break copy-pasted scripts silently. Pin the version in a comment.

⚠️ **`--build-phase` mode uploads ONLY the current target's own dSYM.** It resolves `${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}` and ignores every other dSYM in the same folder (verified empirically against upload-symbols 3.21: two dSYMs staged in the folder → `DSYM Paths: [<app's only>]`). Every dynamic dependency (`product: .framework`) produces its own dSYM, and in a Composition-Root layout those frameworks hold nearly all real code — skipping them guarantees "missing dSYM" console warnings once crashes arrive. Pass the whole `DWARF_DSYM_FOLDER_PATH` directory as an explicit path instead: directory arguments are searched recursively, so app + framework dSYMs upload in one call. Static products (`.staticFramework` / `.staticLibrary`, and SPM's default static linkage) are linked into the app binary and covered by the app's dSYM.

⚠️ `-gsp` and `-p` are metadata tags, not upload switches. Uploads succeed without them, but the console shows version=unknown or files dSYMs in the wrong platform bucket — the failure is invisible on the build side.

```swift
.post(
  script: """
  set -euo pipefail
  # Only upload dSYMs during archive (install) builds.
  if [ "$ACTION" != "install" ]; then exit 0; fi
  if [ "${DEBUG_INFORMATION_FORMAT}" != "dwarf-with-dsym" ]; then exit 0; fi
  # Firebase SDK 12.x — binary is Crashlytics/upload-symbols (not FirebaseCrashlytics/run)
  # Verified: 2026-07 (upload-symbols 3.21)
  SCRIPT=$(find "${BUILD_DIR%Build/*}" -path "*/Crashlytics/upload-symbols" -type f | head -1)
  if [ -z "${SCRIPT}" ]; then
    # This branch only runs on archive builds: a missing tool means shipping
    # an archive whose crashes can never be symbolicated. Fail now, not post-incident.
    echo "error: Crashlytics upload-symbols not found — refusing to archive with un-uploadable dSYMs." >&2
    exit 1
  fi
  "${SCRIPT}" \\
    -gsp "${SRCROOT}/Resources/GoogleService-Info.plist" \\
    -p ios \\
    -- "${DWARF_DSYM_FOLDER_PATH}"
  """,
  name: "Firebase Crashlytics — Upload dSYMs",
  inputPaths: [
    "${DWARF_DSYM_FOLDER_PATH}",
    "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist",
    "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)",
  ],
  basedOnDependencyAnalysis: false
),
```

Required flags:
- `-p ios` — platform tag. Required in explicit-paths mode (only inferred from env in `--build-phase` mode).

Tradeoff to keep: explicit-paths mode uploads synchronously and a failed upload fails the archive (`--build-phase` self-backgrounds and never blocks). Synchronous is the right default — an archive whose dSYMs silently failed to upload ships blind.

### Debug builds: gate collection off instead of uploading

Debug builds produce no dSYM at all (`DEBUG_INFORMATION_FORMAT = dwarf`) and the upload script only runs at archive — so every dev-build crash reaches the console permanently unsymbolicatable and triggers eternal "upload dSYM" nags. Dev crashes are already visible in Xcode; suppress the noise at the source by gating collection per config:

```swift
// Project.swift infoPlist — expands from a per-config build setting
"FirebaseCrashlyticsCollectionEnabled": "$(FIREBASE_CRASHLYTICS_COLLECTION_ENABLED)",
```

```
// Debug.xcconfig
FIREBASE_CRASHLYTICS_COLLECTION_ENABLED = NO
// Release.xcconfig
FIREBASE_CRASHLYTICS_COLLECTION_ENABLED = YES
```

The xcconfig-expanded value is a *string*, and that is fine: `FIRCLSDataCollectionArbiter` accepts NSString or NSNumber and calls `boolValue` (verified in SDK source, Firebase 12.x). The key is read before `FirebaseApp.configure()` returns, so no crash-reporting session ever starts in Debug. Priority order: `setCrashlyticsCollectionEnabled(_:)` sticky value > Info.plist key > FirebaseApp `isDataCollectionDefaultEnabled`.

Post-integration checklist:
- [ ] Build succeeds with zero warnings from the script
- [ ] Archive once and check Crashlytics console dSYM tab within 24h — **verify version metadata matches the build (not 未知/unknown)**, not just that UUIDs appear
- [ ] No required-missing rows for the version you just shipped — including the dynamic frameworks' UUIDs, not only the app binary
- [ ] Debug run reports no Crashlytics session (collection gate active); dev crashes stay out of the console
- [ ] SDK upgrade? Re-verify binary path: `find "${BUILD_DIR%Build/*}" -path "*/Crashlytics/upload-symbols"`
- [ ] Migrating from another project? Diff your `Project.swift` Crashlytics script against the known-working one — do not copy a minimal subset

## Script Sandboxing

Tuist sets `ENABLE_USER_SCRIPT_SANDBOXING = YES` by default. Scripts that access paths outside the build sandbox need:

```swift
// Project-level setting
"ENABLE_USER_SCRIPT_SANDBOXING": .string("NO"),
```

Only disable on the **project that runs the script**. Other projects can keep sandboxing enabled.

Note: moving SwiftFormat to a pre-commit hook eliminates one of the main reasons to disable sandboxing. If only Crashlytics dSYM upload remains, check whether its paths stay within the sandbox before disabling.
