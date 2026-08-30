# Xcode Project Setup Skill

Battle-tested patterns for Xcode project organization, build configuration, and automation. Covers Tuist (primary), XcodeGen, and pure Xcode workflows.

## When to Use

- Setting up a new Xcode project / workspace
- Adding or reviewing xcconfig files
- Adding build phase scripts (linting, formatting, crash reporting)
- Creating or improving a Makefile
- Reviewing project structure decisions
- Migrating from PBXGroup to synced folders
- Handling Xcode "recommended settings" warnings

---

## 1. Workspace & Folder Layout

### Principle

Workspace at the root. Each Xcode project in its own folder. Projects are deployment boundaries - not folder organizers.

### Structure

```
Root/
├── Workspace.swift              ← Tuist workspace definition
├── Makefile
├── .swiftformat
├── Tuist/
│   └── Package.swift            ← SPM deps (or empty if using Project.swift packages:)
│
├── App/                         ← App project (Composition Root)
│   ├── Project.swift
│   ├── Configs/
│   │   ├── Project.xcconfig     ← shared project-level settings
│   │   ├── AppName.xcconfig     ← shared target settings (version, team)
│   │   ├── AppName-Debug.xcconfig
│   │   ├── AppName-Release.xcconfig
│   │   └── AppNameTests.xcconfig
│   ├── Sources/                 ← synced folder (blue)
│   ├── Tests/                   ← synced folder (blue)
│   └── Resources/               ← non-code assets
│
├── CoreKit/                     ← Framework project (Domain + Infrastructure)
│   ├── Project.swift
│   ├── Configs/
│   │   ├── Project.xcconfig
│   │   ├── CoreKitiOS.xcconfig  ← platform-coupled target
│   │   └── CoreKitTests.xcconfig
│   ├── Sources/
│   │   ├── CoreKit/             ← synced folder per target
│   │   ├── CoreKitiOS/          ← synced folder (UIKit layer)
│   │   └── Resources/           ← asset catalogs, strings, design tokens
│   └── Tests/
│       ├── CoreKitTests/        ← synced folder
│       └── CoreKitiOSTests/     ← synced folder
│
└── DevTools/                    ← Optional: debug-only utilities
  ├── Project.swift
  ├── Configs/
  ├── Sources/                 ← synced folder
  └── Tests/
```

### When to Add a Project

Not because "there are many files." Only when:

| Reason | Example |
|--------|---------|
| Different **deployment unit** | Framework vs App |
| Different **access control** | Domain internals hidden from app |
| **Reuse** across apps | Shared framework |
| Isolate **platform coupling** | UIKit target separate from domain |
| Isolate **heavy external SDK** | Google Drive SDK, Firebase |

Within a project, use **folders** for feature grouping - not separate targets. Compiler won't enforce folder boundaries; that's design discipline. But folders are natural seams for future extraction.

### Workspace Definition

**Tuist:**

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
  name: "MyApp",
  projects: [
  "CoreKit",
  "App",
  ],
  generationOptions: .options(
  lastXcodeUpgradeCheck: Version(26, 4, 0)  // ← update on Xcode upgrade
  )
)
```

`lastXcodeUpgradeCheck` prevents the "Update to recommended settings" dialog from appearing on every open.

**XcodeGen:**

```yaml
# project.yml - workspace is auto-created when using projectReferences
projectReferences:
  CoreKit:
  path: CoreKit/CoreKit.xcodeproj
```

**Pure Xcode:** Create `.xcworkspace` manually → drag each `.xcodeproj` into it.

### .gitignore for Generated Projects

When using Tuist or XcodeGen, generated project files should be gitignored - they're derived artifacts:

```gitignore
# Tuist / XcodeGen - regenerated on every `generate`
*.xcodeproj
*.xcworkspace
Derived/          # Tuist-generated plists and bundle accessors

# Xcode user data (always ignore, even without generators)
xcuserdata/

# Build artifacts
*.dSYM
*.dSYM.zip
*.ipa
.build/
.swiftpm/
```

**Without a project generator** (pure Xcode): do NOT gitignore `.xcodeproj` / `.xcworkspace` - they are the source of truth.

---

## 2. Synced Folders (Blue Folders)

### What

Tuist's `buildableFolders: [.folder("Sources")]` creates `PBXFileSystemSynchronizedRootGroup` - Xcode auto-discovers new `.swift` files on disk. No more "file not in project" bugs.

### When to Use

| Content | Use synced folder? | How |
|---------|-------------------|-----|
| Swift source code | ✅ Yes | `buildableFolders: [.folder("Sources")]` |
| Test source code | ✅ Yes | `buildableFolders: [.folder("Tests/MyTests")]` |
| xcassets / .strings / bundles | ❌ No | `resources: ["Sources/Resources/Assets.xcassets", ...]` |
| Mixed source + resources | Split | Sources in synced folder, resources via `resources:` |

### Pitfalls

1. **Resources target can't fully use synced folders** - xcassets and .strings files need explicit `resources:` entries in `Project.swift`. Use `sources:` (regular glob) for the Swift files alongside.

2. **New xcassets/strings still need explicit `resources:` entry** - synced folders auto-discover `.swift` only. Adding a new asset catalog requires updating `Project.swift`.

3. **One synced folder root per target** - each `buildableFolders` entry maps to one target. Multiple targets in the same project need separate source directories (e.g., `Sources/CoreKit/`, `Sources/CoreKitiOS/`).

### Example: Multi-Target Framework

```swift
// CoreKit/Project.swift
targets: [
  .target(
  name: "CoreKit",
  product: .framework,
  buildableFolders: [.folder("Sources/CoreKit")],  // ← synced
  dependencies: [.package(product: "GRDB")]
  ),
  .target(
  name: "CoreKitiOS",
  product: .framework,
  buildableFolders: [.folder("Sources/CoreKitiOS")],  // ← synced
  dependencies: [.target(name: "CoreKit"), .target(name: "Resources")]
  ),
  .target(
  name: "Resources",
  product: .framework,
  sources: ["Sources/Resources/**"],  // ← regular glob (not synced)
  resources: [
      "Sources/Resources/Assets.xcassets",
      "Sources/Resources/Colors.xcassets",
      "Sources/Resources/Strings/**",
  ]
  ),
]
```

---

## 3. SPM Dependencies & Cross-Project References

### SPM Dependencies

Declare SPM packages in the **project that directly imports them** - not in a central manifest.

**Tuist:** Use `packages:` on `Project()` for Xcode-native SPM resolution (recommended). Avoid `Tuist/Package.swift` unless you need Tuist-level SPM management.

```swift
// CoreKit/Project.swift
let project = Project(
  name: "CoreKit",
  packages: [
  .remote(url: "https://github.com/groue/GRDB.swift.git", requirement: .upToNextMajor(from: "7.5.0")),
  ],
  targets: [
  .target(
      name: "CoreKit",
      dependencies: [
    .package(product: "GRDB"),  // ← reference the product name, not the package name
      ]
  ),
  ]
)
```

**XcodeGen:**

```yaml
packages:
  GRDB:
  url: https://github.com/groue/GRDB.swift.git
  majorVersion: 7.5.0

targets:
  CoreKit:
  dependencies:
      - package: GRDB
```

### Cross-Project Dependencies

The App project (Composition Root) references targets from framework projects using relative paths:

**Tuist:**

```swift
// App/Project.swift
.target(
  name: "MyApp",
  dependencies: [
  .project(target: "CoreKit", path: "../CoreKit"),
  .project(target: "CoreKitiOS", path: "../CoreKit"),   // same project, different target
  .project(target: "Resources", path: "../CoreKit"),
  .project(target: "DevTools", path: "../DevTools"),     // different project
  ]
)
```

**XcodeGen:**

```yaml
targets:
  MyApp:
  dependencies:
      - target: CoreKit
    project: CoreKit
```

**Pure Xcode:** Add framework projects to the workspace → each target appears in "Link Binary With Libraries" and "Target Dependencies."

---

## 4. xcconfig Hierarchy

Split build settings: recommended → inline (pbxproj), custom → xcconfig. Never duplicate keys across both.

Full guide: [xcconfig.md](xcconfig.md) — naming convention, what goes where, inline vs xcconfig examples (Tuist / XcodeGen / pure Xcode), target-level keys, Xcode upgrade SOP.

---

## 5. Per-Configuration App Identity (Name & Icon)

Differentiate debug and release builds on the Home Screen — different display name + app icon so you never accidentally demo the debug build.

### Display Name

Use a build setting variable in Info.plist, override per config in xcconfig.

**1. Define variable in xcconfig:**

```xcconfig
// Base.xcconfig
BUNDLE_DISPLAY_NAME = MyApp

// Debug.xcconfig
#include "Base.xcconfig"
BUNDLE_DISPLAY_NAME = MyApp β
```

**2. Reference in Info.plist:**

```swift
// Project.swift (Tuist)
infoPlist: .extendingDefault(with: [
  "CFBundleDisplayName": "$(BUNDLE_DISPLAY_NAME)",
])
```

### Debug App Icon

**1. Create a separate appiconset:**

```
Assets.xcassets/
  AppIcon.appiconset/          ← Release (original)
  AppIcon-Debug.appiconset/    ← Debug (with banner)
```

Use `nanobanana` to overlay a diagonal banner on the original icon:

```bash
nanobanana AppIcon.png "Add a large diagonal banner in the top-left corner with bold white text 'DEBUG'. Use a color that harmonizes with the icon palette. Keep the image as a full-bleed square with no rounded corners or padding." AppIcon-Debug.png
```

> **Full-bleed rule**: App icon assets must be edge-to-edge 1024×1024 squares. Never bake in rounded corners, shadows, or padding — iOS applies its own superellipse mask. AI image tools tend to add decorative rounding; always specify "no rounded corners, full-bleed square" in the prompt.

**2. Set per-config in Tuist target settings:**

```swift
// Project.swift — target settings
settings: .settings(
  configurations: [
    .debug(
      name: "Debug",
      settings: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": .string("AppIcon-Debug"),
      ],
      xcconfig: .relativeToRoot("Configs/Debug.xcconfig")
    ),
    .release(
      name: "Release",
      settings: [:],  // uses default "AppIcon"
      xcconfig: .relativeToRoot("Configs/Release.xcconfig")
    ),
  ]
)
```

> **Why target settings, not xcconfig?** Tuist writes `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` into pbxproj. pbxproj values override xcconfig. You must set the override in the same layer (Tuist target settings → pbxproj) for it to take effect.

---

## 6. Build Phase Scripts

Formatters belong in git hooks, not build phases. All scripts: `set -euo pipefail`, check tool existence, fail loudly.

Full guide: [build-phases.md](build-phases.md) — SwiftFormat pre-commit hook, SwiftLint pre-build, Firebase Crashlytics dSYM upload, script sandboxing.

---

## 7. Shared Schemes

Auto-generated schemes (in `xcuserdata/`) don't persist:
- StoreKit configuration references
- Custom environment variables
- Launch arguments
- Diagnostics settings

Always create **shared schemes** (in `xcshareddata/xcschemes/`) via Tuist:

```swift
schemes: [
  .scheme(
  name: "MyApp",
  shared: true,
  buildAction: .buildAction(targets: ["MyApp"]),
  testAction: .targets(
      [.testableTarget(target: "MyAppTests")],
      configuration: .debug
  ),
  runAction: .runAction(
      configuration: .debug,
      executable: "MyApp"
      // options: .options(storeKitConfigurationPath: "path/to/StoreKit.storekit")
  ),
  archiveAction: .archiveAction(configuration: .release),
  profileAction: .profileAction(configuration: .release, executable: "MyApp"),
  analyzeAction: .analyzeAction(configuration: .debug)
  ),
],
```

---

## 8. Makefile

Self-documenting, DRY `xc` macro, parameterised test targets, version management. Recipes over ~10 lines or containing AppleScript belong in `scripts/` — the Makefile is the menu.

Full guide: [makefile.md](makefile.md) — recipe-vs-script split, simulator vs physical-device targeting, DerivedData strategy, build result verification, adaptation checklist.
Template: [Makefile.template](Makefile.template) · Companion: [xcode-close.applescript](xcode-close.applescript)

---

## 9. Tuist SPM Integration

**Always use Xcode native integration** (`.remote()` in `Project.swift`, `.package(product:)` in dependencies). Do not use `Tuist/Package.swift` XcodeProj-based integration unless explicitly requested — it generates wrapper targets that cause build warnings on Xcode 26.4+ and offers no caching benefit since Xcode 26's native compilation cache.

Full guide: [tuist-spm-integration.md](tuist-spm-integration.md) — decision rule, wrapper target problem, migration steps.

---

## 10. Gotcha Checklist

Quick reference for common Xcode/Tuist pitfalls:

| Pitfall | Defense |
|---------|---------|
| Some recommended keys need target-level, not just project-level | Check diff after "Perform Changes" |
| Copy-pasted build scripts break on SDK version update | Pin version in comment; fail loudly on missing binary |
| Analytics/crash SDK fails silently (no crash, no data) | Check dashboard within 24h post-integration |
| Graceful degradation hides config errors | Add `#if DEBUG` assertions for unexpected empty results |
| xcodebuild incremental build exit 0 despite compile errors | Always double-check: `exit code` AND `grep BUILD FAILED` in log (see below) |
| CLI and IDE land on different DerivedData → SPM re-resolves every build (timeout / slow), and warning counts disagree | Whichever DerivedData a build uses must already contain a populated `SourcePackages/`, or SPM re-fetches from scratch — painful with heavy binary packages (Firebase, gRPC, 800MB+). Fix: pick one strategy for the project and apply it in every wrapper — either pin `-derivedDataPath` to a project-local path everywhere, or omit the flag everywhere so CLI shares the IDE's cache. Mixing the two is what causes this. Define it once (Makefile variable or `xc-env.sh`) and reference it. See [makefile.md](makefile.md) § DerivedData Strategy for the trade-off and the flag constraints that come with sharing |
| `xc-build.sh` vs `xc-build-run.sh` drift | Keep all wrapper scripts identical in error detection logic |
| Hardcoded bundle ID fails on debug builds | Always read from built `.app/Info.plist` via `PlistBuddy`; debug configs often append `.debug` suffix |
| Manual `simctl` sequences (install + launch + guess ID) | Use `make run`; one command, zero guessing |
| `print()` invisible in `log show` / `log stream` / Console.app | `print()` writes to stdout only — not Unified Logging. Use `Logger` (iOS 14+) or `os_log` for logs capturable outside Xcode. See `systematic-debugging` skill for details |
| Tuist XcodeProj-based SPM + binary xcframework → `libtool: 'dummy.o' has no symbols` | Use Xcode native integration (`.remote()` in `Project.swift`) for binary xcframework packages. See [tuist-spm-integration.md](tuist-spm-integration.md) |
| `git commit -- <files>` (pathspec commit) + pre-commit hook `git add` → ghost staged/unstaged diffs | Pathspec commit uses a temporary index; after commit it restores the real index to its pre-commit snapshot, discarding any `git add` the hook performed. Result: HEAD and working tree match, but the index retains stale pre-hook content → phantom staged+unstaged diffs that cancel out. Fix: use `git commit` (index commit) after explicit `git add`; never `git commit -- <files>` when a pre-commit hook calls `git add` |
| `make build` shows zero warnings but Xcode IDE shows many | See § 11 Warning Detection |
| `contentEdgeInsets` deprecated warning (iOS 15+) | Replace with `UIButton.Configuration.contentInsets` (`NSDirectionalEdgeInsets`) |
| `NSMetadataQuery` / `NSObjectProtocol` captured in `@Sendable` closure | If access is serialized on main queue (`.main` notification queue + `@MainActor` task), use `nonisolated(unsafe)` on captured vars |

---

## 11. Warning Detection

CLI `xcodebuild` with project-local DerivedData (`-derivedDataPath .derivedData`) often produces **zero warnings** while the Xcode IDE shows many. Root cause: different DerivedData paths and incremental build states. Projects that share the IDE's cache do not have this problem and need no special target.

### `make warnings` target

Under project-local DerivedData, include a `warnings` Makefile target that:
1. Uses **Xcode's DerivedData** (not project-local) for parity with the IDE
2. Does a **clean build** to surface all diagnostics
3. Filters and counts `warning:` lines

Resolve the IDE directory by the `WorkspacePath` in its `info.plist`. The name suffix hashes the workspace's absolute path, so stale directories accumulate for every location the project has lived at (worktrees, `/tmp` clones) and `-name 'MyApp-*' | head -1` picks an arbitrary one — clean-building a different checkout and reporting its warnings.

```makefile
XCODE_DD = $(shell for d in ~/Library/Developer/Xcode/DerivedData/$(basename $(WORKSPACE))-*; do \
	  [ "$$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$$d/info.plist" 2>/dev/null)" = "$(REPO_ROOT)/$(WORKSPACE)" ] && echo "$$d" && break; \
	done)

warnings:
	@if [ -z "$(XCODE_DD)" ]; then echo "Open project in Xcode first."; exit 1; fi
	xcodebuild clean build -workspace ... -derivedDataPath "$(XCODE_DD)" > warnings.log 2>&1
	grep 'warning:' warnings.log | grep -v 'appintentsmetadataprocessor' | sort -u
```

Full target with build-result verification: [makefile.md](makefile.md) § Warnings Target.

### Agent workflow

- After fixing warnings, always re-run `make warnings` to verify zero count
- The `appintentsmetadataprocessor` warning ("Metadata extraction skipped") is a system noise — ignore it
- Common warning categories: deprecated API, Sendable/concurrency, unused vars, unreachable code

---

## 12. xcodebuild Error Detection

xcodebuild incremental builds can return exit 0 despite compile errors. Always use dual failure detection.

Full guide: [xcodebuild-error-detection.md](xcodebuild-error-detection.md) — required pattern, consistency rule, `CODE_SIGNING_ALLOWED=NO`.
