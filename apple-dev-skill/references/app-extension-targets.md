# App Extension Targets

What the extension boundary adds on top of ordinary modularization: which targets get the extension-safe API flag, how shared code reaches app-only capabilities, why every bundle shares one version, and why resources go missing only inside an extension.

## When to Apply / Not for

Apply when adding a widget, share, notification, intents, or keyboard extension; when moving code into a module an extension links; or when something works in the app and fails only inside an extension.

Not for module layering in general (→ [modular-architecture](modular-architecture.md)) nor for the Settings language picker (→ [localization-bundle-discovery](localization-bundle-discovery.md)).

## Extension-Safe API Flag: Which Targets Get It

Set `APPLICATION_EXTENSION_API_ONLY = YES` on every extension target **and on every module in an extension's transitive dependency graph**. Never set it on the app target or on modules only the app links — there it rejects legitimate `UIApplication.shared` calls and buys nothing.

What Apple enforces is the API use, not the setting: "The App Store rejects any app extension that links to such frameworks or that otherwise uses unavailable APIs" (App Extension Programming Guide). The setting is what turns that rejection into a build-time failure:

- On a module, the compiler checks that module's own code — `UIApplication.shared` and every other API marked unavailable in extensions fails to compile.
- On the extension target, the linker additionally warns about each linked dylib not built with the flag ("linking against a dylib which is not safe for use in application extensions").

Static linkage removes the second net. A static module is merged into the extension's binary, so the linker has no dylib marker to inspect and an unsafe call ships without a warning. Under static linkage — the default in modular-architecture.md — the module's own flag is the only guard, which is why the rule follows the dependency graph rather than stopping at the extension target.

Swift packages take no build setting. Since Xcode 13, a package declaration that uses an extension-unavailable API must itself be annotated `@available(iOSApplicationExtension, unavailable)` for the package to be usable from both the app and its extensions (Xcode 13 release notes).

## App-Only Capabilities in Shared Modules

A shared module that needs an app-only capability — opening a URL through `UIApplication`, finding the key window, reading application state — has two ways to compile under the flag:

1. **Inject it.** Each host passes the capability in; the extension passes a no-op or its own equivalent.

   ```swift
   public struct HostCapabilities {
       public var isMainApp: Bool
       public var openURL: (URL) -> Void
   }
   // App:       HostCapabilities(isMainApp: true, openURL: { UIApplication.shared.open($0) })
   // Extension: HostCapabilities(isMainApp: false, openURL: { _ in })
   ```

2. **Fence the declaration.** Mark it `@available(iOSApplicationExtension, unavailable)`. The annotation propagates: every caller must be unavailable in extensions too, so it fits leaf helpers that only app-side screens call, not code on a path the extension shares.

Choose per declaration; a module can use both.

## One Version Source for Every Bundle

An extension's `CFBundleShortVersionString` and `CFBundleVersion` must equal the host app's. A mismatch raises an Xcode build warning ("The CFBundleShortVersionString of an app extension … must match that of its containing parent app") and App Store Connect upload warning ITMS-90473.

Keep `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in one `Version.xcconfig` that the app target and every extension target `#include` (layout in [xcconfig](xcconfig.md)); in a Tuist manifest, one constant every target's settings read. A per-target copy drifts on the first bump that edits only the app's file. [Makefile.template](Makefile.template)'s `VERSION_FILE` points at that shared file.

## `Bundle.main` Is the Extension

Inside an extension, `Bundle.main` is the `.appex`, not the host `.app`. Images, strings, and plists that live in the app target resolve to nil there — `UIImage(named:)`, `Bundle.main.url(forResource:withExtension:)`, `NSLocalizedString` without a bundle — while the identical call works in the app, so the bug never shows up in app-side testing.

Put shared resources in a module both targets link and resolve them through that module's bundle: `Bundle.module` (SPM targets, and Tuist targets with resources), or `Bundle(for: SomeClassInTheModule.self)` for a hand-made framework target. Do not derive the host bundle by walking up from the `.appex` path; that hard-codes the bundle layout and fails silently when it changes.
