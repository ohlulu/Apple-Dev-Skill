# Build Phase Scripts

## Principles

1. **`set -euo pipefail`** at the top — fail on any error
2. **Check tool existence** before running — `command -v tool >/dev/null 2>&1`
3. **Fail loudly on critical path** — `exit 1` if binary not found
4. **Formatters belong in git hooks, not build phases** — build phases format on every build (including archive), leaving uncommitted diffs; pre-commit hooks format only staged files at commit time

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

⚠️ **`--build-phase` is not enough by itself.** Firebase SDK 12.x requires `-gsp` and `-p ios` to tag uploads with project + platform metadata. Without them, uploads succeed but show 版本=未知 (version=unknown) in the console, and some dSYMs may be skipped entirely. See: Sotto 2026-06-01 follow-up in `2026-03-13-crashlytics-dsym-silent-failure.md`.

```swift
.post(
  script: """
  # Only upload dSYMs during archive (install) builds.
  if [ "$ACTION" != "install" ]; then exit 0; fi
  if [ "${DEBUG_INFORMATION_FORMAT}" != "dwarf-with-dsym" ]; then exit 0; fi
  # Firebase SDK 12.x — binary is Crashlytics/upload-symbols (not FirebaseCrashlytics/run)
  # Verified: 2026-06
  SCRIPT=$(find "${BUILD_DIR%Build/*}" -path "*/Crashlytics/upload-symbols" -type f | head -1)
  if [ -n "${SCRIPT}" ]; then
    "${SCRIPT}" \\
      -gsp "${SRCROOT}/Targets/<App>/Resources/GoogleService-Info.plist" \\
      -p ios \\
      --build-phase
  else
    echo "warning: Crashlytics upload-symbols not found — dSYMs will NOT be uploaded."
  fi
  """,
  name: "Firebase Crashlytics — Upload dSYMs",
  inputPaths: [
    "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}",
    "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}",
    "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist",
    "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist",
    "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)",
  ],
  basedOnDependencyAnalysis: false
),
```

Required flags:
- `-gsp <path>` — Firebase project association. Without this, console shows 版本=未知.
- `-p ios` — platform tag. Without this, dSYM may land in wrong platform bucket.
- `--build-phase` — read `DWARF_DSYM_FOLDER_PATH` from env (don't pass dSYM paths manually).

Post-integration checklist:
- [ ] Build succeeds with zero warnings from the script
- [ ] Archive once and check Crashlytics console dSYM tab within 24h — **verify version metadata matches the build (not 未知/unknown)**, not just that UUIDs appear
- [ ] No required-missing rows for the version you just shipped
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
