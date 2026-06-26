# xcconfig Hierarchy

## Principle

Split build settings into two groups by audience:

| Setting type | Where | Why |
|-------------|-------|-----|
| Xcode **recommended** settings | Inline in `Project.swift` → pbxproj | Checker only reads pbxproj; xcconfig is invisible to it |
| **Custom** project settings | xcconfig files | Centralized, readable, diffable |

**Never put the same key in both places.** Inline wins over xcconfig at the same level, creating invisible override confusion.

This split applies regardless of whether you use Tuist, XcodeGen, or pure Xcode. The underlying Xcode build system behavior is the same.

## Naming Convention

```
{Project}/Configs/
├── Project.xcconfig              ← project-wide: Swift version, concurrency, warnings
├── {TargetName}.xcconfig         ← target shared: team, version, bundle ID base
├── {TargetName}-Debug.xcconfig   ← debug override (#include base)
├── {TargetName}-Release.xcconfig ← release override (#include base)
└── {TargetName}Tests.xcconfig    ← test target settings
```

The config-specific files `#include` their shared base:

```xcconfig
// AppName-Debug.xcconfig
#include "AppName.xcconfig"

PRODUCT_BUNDLE_IDENTIFIER = com.company.app.debug
```

## What Goes Where

**Project.xcconfig** (shared across all targets in this project):

```xcconfig
SWIFT_VERSION = 6
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
SWIFT_APPROACHABLE_CONCURRENCY = YES

// Type-check performance guard (Debug only)
OTHER_SWIFT_FLAGS[config=Debug] = $(inherited) -Xfrontend -warn-long-expression-type-checking=300
```

> ⚠️ `SWIFT_VERSION` here is **not enough on its own** under Tuist — its
> `.recommended` default injects `SWIFT_VERSION = 5.0` at the target level,
> which outranks this project xcconfig. See *Tuist default settings shadow
> project xcconfig* below before trusting this value.

**{TargetName}.xcconfig** (shared target settings):

```xcconfig
DEVELOPMENT_TEAM = XXXXXXXXXX
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor  // or nonisolated for tests
```

**Inline — recommended settings only:**

Tuist:

```swift
settings: .settings(
  base: [
  // These MUST be inline — checker only reads pbxproj
  "ENABLE_MODULE_VERIFIER": .string("YES"),
  "MODULE_VERIFIER_SUPPORTED_LANGUAGES": .string("objective-c objective-c++"),
  "MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS": .string("gnu11 gnu++14"),
  "SWIFT_EMIT_LOC_STRINGS": .string("YES"),
  "STRING_CATALOG_GENERATE_SYMBOLS": .string("YES"),
  "ENABLE_USER_SCRIPT_SANDBOXING": .string("YES"),
  "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOL_EXTENSIONS": .string("YES"),
  ],
  configurations: [
  .debug(name: "Debug", xcconfig: "Configs/Project.xcconfig"),
  .release(name: "Release", xcconfig: "Configs/Project.xcconfig"),
  ]
)
```

XcodeGen:

```yaml
settings:
  base:
  ENABLE_MODULE_VERIFIER: YES
  MODULE_VERIFIER_SUPPORTED_LANGUAGES: "objective-c objective-c++"
  configs:
  Debug:
      xcconfig: Configs/Project.xcconfig
  Release:
      xcconfig: Configs/Project.xcconfig
```

Pure Xcode: set recommended settings directly in pbxproj via Xcode UI → Build Settings tab. Use xcconfig for custom settings via `baseConfigurationReference`.

## Target-Level Recommended Settings

Some recommended settings require target-level declaration — the checker doesn't do project→target inheritance lookup:

| Key | Requires target-level? |
|-----|----------------------|
| `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOL_EXTENSIONS` | ✅ if target has asset catalog |
| `MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS` | ✅ every framework/app target |

```swift
// Target-level settings (in addition to project-level)
.target(
  name: "MyFramework",
  settings: .settings(
  base: [
      "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOL_EXTENSIONS": .string("YES"),
      "MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS": .string("gnu11 gnu++14"),
  ],
  configurations: [...]
  )
)
```

## Tuist Default Settings Shadow Project xcconfig (the Swift-version trap)

**Setting `SWIFT_VERSION` only in project-level `Project.xcconfig` does NOT put
the project on that Swift language mode under Tuist.** Tuist's
`Settings.defaultSettings` defaults to `.recommended`, which injects a curated
set of build settings — including `SWIFT_VERSION = 5.0` — as **inline,
target-level** settings on every target it generates.

Build-setting resolution order (highest wins):

```
target inline  >  target xcconfig  >  project inline  >  project xcconfig
```

The injected target-level `SWIFT_VERSION = 5.0` therefore silently overrides
`SWIFT_VERSION = 6` declared in project `Project.xcconfig`. The whole workspace
compiles in **Swift 5 language mode** while the xcconfig reads `6`.

**Why it hides so well:** `SWIFT_STRICT_CONCURRENCY = complete` +
`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is the *Swift-5 migration mode*, not
Swift 6 — it builds clean and looks done. The only honest signals are Xcode's
Build Settings pane (shows "Swift 5") and `-showBuildSettings`.

**`defaultSettings` does not cascade project→target.** Each `Settings` object
carries its own `defaultSettings` (defaulting to `.recommended`). A target that
declares its own `settings:` block uses *that* block's default, not the
project's — so setting it once at project level fixes nothing for targets.

**Fix — exclude the key on every `Settings` object (project + each target):**

```swift
let swift6Defaults: DefaultSettings = .recommended(excluding: ["SWIFT_VERSION"])

// project
settings: .settings(base: [...], configurations: [...], defaultSettings: swift6Defaults)

// every target with its own settings
.target(name: "Foo", settings: .settings(base: [...], defaultSettings: swift6Defaults))
```

With the injection removed, the value resolves down to project `Project.xcconfig`
— keeping the xcconfig the single source of truth. A target with **no**
`settings:` block still needs one (even just
`.settings(defaultSettings: swift6Defaults)`), because Tuist applies
`.recommended` to every target independently.

**Verify with the resolved value, never the xcconfig text:**

```bash
xcodebuild -workspace App.xcworkspace -scheme App -showBuildSettings \
  -configuration Debug 2>/dev/null | grep ' SWIFT_VERSION '
# → SWIFT_VERSION = 6
```

A text-only xcconfig drift audit (comparing `Project.xcconfig` files) will pass
while the build is on Swift 5 — it cannot see the Tuist injection. Trust
`-showBuildSettings`.

## Xcode Upgrade SOP

1. Update `Workspace.swift` → `lastXcodeUpgradeCheck` to new version
2. `make gen` → open Xcode
3. If "recommended settings" dialog appears:
   - Save pbxproj backup: `cp *.xcodeproj/project.pbxproj /tmp/before.pbxproj`
   - Click **Perform Changes**
   - `diff /tmp/before.pbxproj *.xcodeproj/project.pbxproj | grep "^>"` → find new keys
   - Add new keys to `Project.swift` inline (project or target level per diff)
4. `make gen` → confirm dialog no longer appears
