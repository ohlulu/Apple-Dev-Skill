---
name: apple-dev-skill
description: >-
  Use when working in any iOS / iPadOS / macOS app project — load on
  Turn 1 if cwd is an Xcode/Tuist project or has .swift files in an
  app target. Load even when the prompt is plain-language design /
  UX talk ("this page", "the push feels wrong", "background should
  be grey") not naming Apple APIs — project type decides, not
  phrasing. Covers UIKit, SwiftUI bridging, Xcode/Tuist setup,
  xcconfig, build phases, Makefile, Swift conventions.
  NOT for server-side Swift, Linux Swift, CLI tools, or
  platform-agnostic SPM libs.
  Trigger words: UIKit, UIViewController, UISplitViewController,
  UINavigationController, Auto Layout, UIViewRepresentable, Xcode,
  xcconfig, Tuist, Makefile, Project.swift, push, transition, sheet,
  popover, tab bar, navigation, keyboard, gesture, animation, layout,
  iPad, iPhone, iOS, iPadOS, macOS app, 画面, 頁面, 按鈕, 卡片,
  切換, 推, 返回, 底色, 佈局, 動畫, 導航, 工具列, 彈窗,
  鍵盤, 手勢, 專案設定, 建置設定.
---

# Apple Dev Skill

Unified reference for Apple platform app development — UIKit/UI patterns, Xcode project setup, and Swift coding conventions scoped to app contexts.

## Precedence Rule

When a project already has a clear, established local convention, follow it by default.
Ask the user only when local conventions are ambiguous, conflicting, or likely harmful.
Do not silently replace a strong project convention with this skill's defaults.

## Debugging Heuristic: Stop Stacking Suppression Layers

When fixing a visual / animation / layout bug:

- If layer N fixes the symptom and reveals a new one, layer N was
  probably a workaround. Stop and find the root cause before adding
  layer N+1.
- A real fix usually replaces N earlier suppression layers, not adds
  to them. If the patch you're about to commit is *additive* to a
  growing list of `performWithoutAnimation` / `setDisableActions` /
  `removeAllAnimations` / hidden-by-default flags, it is almost
  certainly a workaround.
- Before adding any second suppression, run the four-step diagnostic:
  (1) minimal repro, (2) vendor changelog / release notes, (3) web
  research with the exact API name, (4) Instruments Core Animation
  profiler. See `implicit-animations.md` → "Anti-Pattern: Symptom
  Stacking" for the long form.
- iOS version differences matter — a behavior that's broken on iOS 26
  may have worked on iOS 18, or may have been fixed in a point
  release. See `ios-26-behavior-changes.md` for the deltas we've
  catalogued.

This heuristic is mandatory when working on animation-adjacent bugs.
The codebase has been bitten by it; the skill exists in part because
we stacked four layers before stopping.

## Topic Router

Consult the reference file for each topic relevant to the current task. Apply all rules from the matched references — do not skip them for convenience.

### UIKit / UI Patterns

| Topic | Reference |
|-------|-----------|
| File structure (property ordering, extensions, layout placement for UIViewController, UIView, UITableViewCell, and other UIKit subclasses) | [file-structure](references/file-structure.md) |
| Animation (duration, curve, fade defaults, expand/collapse choreography, stagger reveal, custom layout view height animation pitfalls) | [animation](references/animation.md) |
| Zoomable image preview with hero transition + pan dismiss (tap-to-enlarge avatar / image viewer in the IG / Photos.app / Telegram style: `.overFullScreen` not `.custom` so blur backdrop works; UIScrollView zoom-target centring via `bounds.size =` + symmetric `contentInset` + explicit `contentOffset` snap, NOT manual `center` or `frame.origin` which the scroll view resets every layout pass; setting `frame` on a transformed view inflates `bounds` by `1/scale`; circular `cornerRadius` scales with zoom transform to stay a perfect circle; hero snapshot in `transitionContext.containerView` coords with `alpha = 0` source hiding, restored on cancel; manual pan-to-dismiss instead of `UIPercentDrivenInteractiveTransition` for multi-axis follow-finger feel; `shouldRecognizeSimultaneouslyWith` + lenient `shouldBegin` to coexist with `scrollView.panGestureRecognizer`; re-entry identity guard `panSnapshot === snapshot` in completion handlers; third-party VC self-set `transitioningDelegate` trap that blanks `.formSheet` presenters (TOCropViewController #486); TOCropViewController circular crop + JPEG storage produces white-corner avatars that the preview must re-mask) | [zoomable-image-preview](references/zoomable-image-preview.md) |
| Implicit animations (CALayer/UIKit animations that fire WITHOUT a UIView.animate block: CAGradientLayer.colors crossfade, UISegmentedControl pill on delta, UISwitch.isOn animated default, diffable first-apply against empty source, iOS 26 .zero-frame settling artifact; bind-before-load sync-fire trap and the load → sync → bind reorder fix that disambiguates it from the iOS 26 layout regression; disable-at-source recipes via layer.actions = NSNull; per-control vs per-call-site vs per-view suppression; mount-state hygiene checklist; "symptom stacking" anti-pattern with empty-body test, differential check, and cheap-first investigation order; iOS version delta table for each behavior) | [implicit-animations](references/implicit-animations.md) |
| Compound cell row animation (animating row insert/remove in a settings-style compound card cell, UISwitch distortion trap, performBatchUpdates vs invalidateLayout in compositional layout, UIStackView isHidden animation) | [compound-cell-row-animation](references/compound-cell-row-animation.md) |
| Cell registration (CellRegistration vs legacy register/dequeue, pitfalls, handler lifecycle, retain cycles, dynamic cell types) | [cell-registration](references/cell-registration.md) |
| List composition (heterogeneous cells, row/item controllers, section controllers, load-more controller, pagination seam, diffable, compositional layout, default shapes, sectionHeaderTopPadding gotcha, sticky header bleed layers) | [list-composition](references/list-composition.md) |
| Screen composition / composer (programmatic controller instantiation, dependency wiring, navigation closures, scene root composition) | [composer](references/composer.md) |
| UISplitViewController on iOS 26 (primary column is a floating overlay not a flush sibling, secondary bounds span the full screen, detail content must anchor to safeAreaLayoutGuide leading/trailing, composer ordering, .tile is ignored, push transitions inside secondary nav slide across full width and land under master overlay, SecondaryColumnHost wrapper pattern, axe describe-ui diagnostic for full-width clipping, .zero-frame settling animation root cause + setViewControllerWithoutAnimation wrapper with viewController.view.layoutIfNeeded after swap, async vs sync state loads after / during mount and the bind-before-load trap that masquerades as the iOS 26 regression) | [split-view-controller](references/split-view-controller.md) |
| iOS 26 behavior changes catalog (consolidated index of deltas from iOS 18: Liquid Glass sidebar overlay, primaryBackgroundStyle vs primaryBackgroundEffect, setViewController .zero-frame regression, pushViewController same regression fixed in 26.2, push transition full-width slide; what did NOT change but was assumed to; diagnostic workflow when suspecting an iOS 26 regression) | [ios-26-behavior-changes](references/ios-26-behavior-changes.md) |
| Image resizing (UIGraphicsImageRenderer, preparingThumbnail, CGImageSource downsampling, template icon sizing, display vs encode) | [image-resizing](references/image-resizing.md) |
| Self-sizing (systemLayoutSizeFitting, preferredContentSize, self-sizing cells, complete constraint chains, auto-resize-on-layout-pass trap where reading initializer constants silently reverts external mutations) | [self-sizing](references/self-sizing.md) |
| Step transition sizing (wizard / multi-step card with size-changing children, Cassowary compromise between two pinned child VCs, explicit containerHeightConstraint + systemLayoutSizeFitting + scrollView preferred-height bridge + snapshot-and-reparent outgoing child) | [step-transition-sizing](references/step-transition-sizing.md) |
| Vertical alignment (centerY vs baseline, mixed-size text, manual-frame containers, measuring real button height) | [alignment](references/alignment.md) |
| UIButton.Configuration (Configuration vs legacy API, titleTextAttributesTransformer, silent override trap) | [uibutton-configuration](references/uibutton-configuration.md) |
| UIButton icon badge (small circular icon overlay, .custom type, icon as subview not setImage, highlight via touchDown/Up) | [uibutton-icon-badge](references/uibutton-icon-badge.md) |
| View wrapping (wrapped(insets:), container padding, section decoration helpers, when to use vs manual wrapper) | [view-wrapping](references/view-wrapping.md) |
| Content overflow detection (two-pass layout, actual vs estimated measurement, dynamic collapse/expand triggers) | [overflow-detection](references/overflow-detection.md) |
| Shadow and clipping (CALayer shadow visibility, contentView.clipsToBounds default, ancestor chain check, deferred visual initialization, UILabel backgroundColor not clipped by cornerRadius, iOS 26 sheet double-background color shift) | [shadow-and-clipping](references/shadow-and-clipping.md) |
| Keyboard avoidance (scroll view inset adjustment, keyboardWillChangeFrame, animation sync, inputView handling, first responder scrolling) | [keyboard-avoidance](references/keyboard-avoidance.md) |
| Menu vs popover (UIMenu for flat option selection, UIPopover for custom UI, decision rule, sizing pitfalls, migration guide) | [menu-vs-popover](references/menu-vs-popover.md) |
| Popover tooltip (UIPopoverPresentationController safe-area centering trap, iPhone adaptation, preferredContentSize calculation, arrow direction, tap target sizing, dismiss behavior) | [popover-tooltip](references/popover-tooltip.md) |
| Localizable.strings escapes (Apple `.strings` only supports `\Uxxxx` capital U; lowercase `\u2014` silently parses as literal `u2014` at runtime; prefer direct UTF-8 characters for em dash, ellipsis, smart quotes; CI grep audit) | [localizable-strings-escapes](references/localizable-strings-escapes.md) |
| Localization bundle discovery (framework-only `.lproj` makes iOS hide the Settings Preferred Language picker; main bundle is the only source iOS consults; explicit `CFBundleLocalizations` + `CFBundleAllowMixedLocalizations`; Tuist Info.plist recipe; reinstall to refresh Settings cache; `CFBundleDevelopmentRegion` is not the supported-languages list) | [localization-bundle-discovery](references/localization-bundle-discovery.md) |
| Auto Layout spacing and distribution (setCustomSpacing, CSS flex vs AL, spacer view pitfalls, independent top/bottom pinning, flexible gap strategies) | [autolayout-spacing](references/autolayout-spacing.md) |
| Navigation bar appearance (UINavigationBarAppearance slots, iOS 26 backgroundColor breaking change, Liquid Glass compatibility, three-slot consistency, large title collapse scroll tracking, alwaysBounceVertical, split appearance for opaque chrome, embedded UISearchBar independent background) | [navigation-bar-appearance](references/navigation-bar-appearance.md) |
| Testing principles (test levels, async spies, assertion strategy, memory leak tracking) | [testing-principles](references/testing-principles.md) |
| UIKit testing (lifecycle simulation, semantic list helpers, reuse/visibility tests, pagination integration tests, screen integration tests) | [testing](references/testing.md) |
| Eliminating objc_setAssociatedObject (UIAction closures, subclass stored properties, wrapper views, session object lifetime, delegate conflict pitfall, wrapper identity trap) | [associated-objects](references/associated-objects.md) |
| UIViewRepresentable bridge (two golden rules, diff-based updateUIView, async delegate→state, coordinator callbacks, programmatic vs user change detection, pre-rendered bitmaps for scroll performance, Swift 6 @preconcurrency delegates) | [uiview-representable](references/uiview-representable.md) |
| iCloud ubiquity container (NSMetadataQuery discovery, startDownloadingUbiquitousItem, progress-based timeout, bulk download, ubiquitousItemDownloadingErrorKey, NSUbiquitousContainers Files app visibility, fresh-install restore) | [icloud-ubiquity](references/icloud-ubiquity.md) |

### Xcode / Project Setup

| Topic | Reference |
|-------|-----------|
| Xcode project setup (workspace layout, synced folders, SPM deps, cross-project refs, app identity, shared schemes, gotchas, warning detection) | [xcode-project-setup](references/xcode-project-setup.md) |
| xcconfig hierarchy (naming convention, inline vs xcconfig, target-level keys, Xcode upgrade SOP) | [xcconfig](references/xcconfig.md) |
| Build phase scripts (SwiftFormat pre-commit hook, SwiftLint pre-build, Firebase Crashlytics dSYM upload, script sandboxing) | [build-phases](references/build-phases.md) |
| Makefile (design principles, simulator destination, run target, adaptation checklist) | [makefile](references/makefile.md) |
| Makefile template | [Makefile.template](references/Makefile.template) |
| Tuist SPM integration (native vs XcodeProj-based, wrapper target problem, migration steps) | [tuist-spm-integration](references/tuist-spm-integration.md) |
| xcodebuild error detection (dual failure detection, exit code + BUILD FAILED grep, CODE_SIGNING_ALLOWED=NO) | [xcodebuild-error-detection](references/xcodebuild-error-detection.md) |
| CLI distribution signing (xcodebuild exportArchive cloud signing relies on Xcode Settings → Accounts OAuth session, not ASC API key; "Failed to find an account" / "Cloud signing permission error" both mean the same missing-account state; do NOT mint a local Apple Distribution cert as a workaround) | [cli-distribution-signing](references/cli-distribution-signing.md) |

### Swift Coding Style (App Context)

| Topic | Reference |
|-------|-----------|
| Swift conventions (opaque vs existential types, type design, protocols, error handling, API design, file organization) | [swift-style](references/swift-style.md) |
