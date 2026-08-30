# Tuist SPM Integration: XcodeProj-based vs Xcode Native

## Two Integration Modes

Tuist supports two ways to integrate SPM packages. They are **not interchangeable** — each produces a fundamentally different project structure.

### Xcode Native (`.remote()` in `Project.swift`)

```swift
// Project.swift
let project = Project(
  packages: [
    .remote(url: "https://github.com/firebase/firebase-ios-sdk", requirement: .upToNextMajor(from: "11.0.0")),
  ],
  targets: [
    .target(
      dependencies: [
        .package(product: "FirebaseAnalytics"),
      ]
    ),
  ]
)
```

- Xcode resolves and links packages directly (same as adding via File → Add Package in Xcode)
- No wrapper targets generated
- Binary xcframeworks linked as-is

### XcodeProj-based (`Tuist/Package.swift`)

```swift
// Tuist/Package.swift
let package = Package(
  name: "Dependencies",
  dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
  ]
)

// Project.swift
.target(
  dependencies: [
    .external(name: "FirebaseAnalytics"),
  ]
)
```

- Tuist resolves packages and generates **Xcode targets** for each SPM product
- Binary xcframeworks get **wrapper static framework targets** with modulemaps
- These wrapper targets may compile source files from the upstream package (e.g., `dummy.m`) — see "The Wrapper Target Problem" below

## The Wrapper Target Problem

Packages like Firebase include empty source files (`dummy.m`) to satisfy SPM's "at least one source file per target" requirement. When Tuist creates wrapper targets for these:

1. `dummy.m` compiles to `dummy.o` with zero exported symbols
2. `libtool` packages `dummy.o` into a static library
3. **Xcode 26.4+**: libtool warns `'dummy.o' has no symbols` (stricter than previous Xcode versions)

This produces 5-10+ warnings per project that use Firebase/Google SDKs via XcodeProj-based integration.

**Xcode native integration does not create wrapper targets** → no `dummy.o` → no warning.

## Decision Rule

**Always use Xcode native (`.remote()` in `Project.swift`).** Do not use `Tuist/Package.swift` unless the user explicitly requests it.

### Why not XcodeProj-based?

The only historical justification was **Tuist's old `tuist cache warm`** — it required XcodeProj-based integration to generate targets, build them, and cache as xcframeworks.

Xcode 26 introduced a **native compilation cache** (`COMPILATION_CACHE_ENABLE_CACHING=YES`) that operates at the build-system level. Tuist supports it via `enableCaching: true` in `Tuist.swift`. This cache works with `.remote()` packages — no XcodeProj-based integration needed.

XcodeProj-based integration now only adds overhead:
- Generates wrapper targets for every SPM product
- Binary xcframework wrappers compile empty `dummy.m` — see "The Wrapper Target Problem" above for the resulting `libtool` warning
- More generated Xcode projects to maintain
- No caching benefit over Xcode native

**Do not mix** `.external()` and `.package()` for packages that share transitive dependencies — version resolution conflicts. If migrating, move all packages at once.

## Migration: XcodeProj-based → Xcode Native

1. Move `.package()` entries from `Tuist/Package.swift` to `Project.swift` `packages:` as `.remote()`
2. Change dependency references from `.external(name: "X")` to `.package(product: "X")`
3. Clear stale state:
   ```bash
   rm -rf MyApp.xcworkspace/xcshareddata/swiftpm
   tuist clean
   tuist install
   tuist generate
   ```
4. Verify: `make warnings` should show zero `libtool` warnings
