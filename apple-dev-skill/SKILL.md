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
  iPad, iPhone, iOS, iPadOS, macOS app, 畫面, 頁面, 按鈕, 卡片,
  切換, 推, 返回, 底色, 佈局, 動畫, 導航, 工具列, 彈窗,
  鍵盤, 手勢, 專案設定, 建置設定.
---

# Apple Dev Skill

Unified reference for Apple platform app development — UIKit/UI patterns, Xcode project setup, and Swift coding conventions scoped to app contexts.

## Precedence Rule

When rules conflict, resolve in this order:

| Conflict | Winner | Why |
|----------|--------|-----|
| Explicit user instruction vs anything in this skill | User instruction | The user owns the project; this skill supplies defaults, not law |
| Clear, established project convention vs this skill's default | Project convention | Local consistency beats global preference — a mixed style is worse than either style |
| Ambiguous or mutually conflicting local conventions vs this skill's default | Ask the user with short options | Guessing between competing conventions is the classic source of rework |
| Project convention that is likely harmful (correctness / safety) | Raise it explicitly; follow neither silently | Silently copying a bug propagates it; silently "fixing" it surprises the team |

Do not silently replace a strong project convention with this skill's defaults.

## Debugging Heuristic: Stop Stacking Suppression Layers

When fixing a visual / animation / layout bug:

- If layer N fixes the symptom and reveals a new one, layer N was
  probably a workaround. Stop and find the root cause before adding
  layer N+1. A real fix usually replaces N earlier suppression
  layers, not adds to them.
- If the patch you're about to commit is *additive* to a growing list
  of `performWithoutAnimation` / `setDisableActions` /
  `removeAllAnimations` / hidden-by-default flags, it is almost
  certainly a workaround.
- Before adding any second suppression, run the four-step diagnostic:
  (1) minimal repro (empty-body test), (2) vendor changelog / release
  notes, (3) web research with the exact API name, (4) geometry
  logging per layout pass + cross-iOS-version simulator comparison
  (same code, different runtime). See `implicit-animations.md` →
  "Anti-Pattern: Symptom Stacking" for the long form. Instruments'
  Core Animation profiler is a user-run option — suggest it to the
  user; do not attempt to drive it yourself.
- iOS version differences matter — a behavior that's broken on iOS 26
  may have worked on iOS 18, or may have been fixed in a point
  release. See `ios-26-behavior-changes.md` for the catalogued deltas.

This heuristic is mandatory when working on animation-adjacent bugs.

Cross-trigger: if a visual / animation / layout fix fails once, load the
global `systematic-debugging` skill and follow its phases. After a second
failed fix, web search with the exact API name and symptom is mandatory —
stop iterating on local guesses.

## UI Verification Loop (mandatory Definition of Done for UI work)

Any task that changes what the user sees — new screen, layout change,
color / spacing / typography tweak, animation adjustment — is done only
with screenshot evidence, never from code reading:

1. Implement, build, run, and capture a simulator screenshot (axe /
   simctl), resized before reading (`sips --resampleWidth 640 <file>`).
2. Inspect the screenshot against the intent. When a mockup or
   reference screenshot exists, read both side by side and list every
   visible difference — spacing, typography, color, alignment, shadows,
   missing elements.
3. Fix, re-capture, repeat. Report done only when the screenshot
   matches the intent (or the diff list is empty / every remaining
   difference has an explicit platform-idiom justification).

Never claim a visual change works from code alone — the screenshot is
the evidence. Skipping this loop is the single largest source of
repeated user corrections.

## Topic Router

Consult the reference file for each topic relevant to the current task. Apply all rules from the matched references — do not skip them for convenience.

Family rule: when a reference is a special case of another, both router rows must state the boundary — the parent row lists its special-case children (→ links), and the child row names the parent and its NOT-for scope. A reference joining a family must also declare the same boundary in its own "When to Apply / Not for" section.

### UIKit / UI Patterns

| Topic | Reference |
|-------|-----------|
| File structure for UIKit subclasses. Property ordering, extension-per-responsibility, layout section placement for UIViewController / UIView / cells. | [file-structure](references/file-structure.md) |
| Animation defaults and choreography — linear-fade defaults, spring expand/collapse choreography, custom-layout height animation, text expand/collapse, staggered entrance. NOT for motion with no authored animate block (→ implicit-animations) nor compound-cell row insert/remove (→ compound-cell-row-animation). | [animation](references/animation.md) |
| Zoomable image preview (IG / Photos.app-style tap-to-enlarge viewer). Hero grow transition, pinch zoom, follow-finger pan dismiss — covers UIScrollView centring traps, presentation-style requirements, and gesture coexistence. | [zoomable-image-preview](references/zoomable-image-preview.md) |
| Implicit animations — motion firing WITHOUT any UIView.animate block you wrote: layer-property assignment, control state re-animation, layout-pass animations. Catalog + disable-at-source recipes, bind-before-load sync-fire trap, symptom-stacking diagnostic. Start here when "something animates but there is no animate {} to grep". | [implicit-animations](references/implicit-animations.md) |
| Compound cell row animation — special case of animation.md: animating row insert/remove inside a settings-style compound card cell. UISwitch distortion trap, performBatchUpdates vs invalidateLayout. Read animation.md first for defaults. | [compound-cell-row-animation](references/compound-cell-row-animation.md) |
| Cell registration. CellRegistration vs legacy register/dequeue, handler lifecycle, retain cycles, dynamic cell types. | [cell-registration](references/cell-registration.md) |
| Diffable data source. Hashable-not-Identifiable constraint, two identifier patterns, reconfigureItems as the content-update channel (never folded into an animated apply — that strands stack-arranged subviews half-hidden), iOS 15 semantic changes, cross-framework sharing mistakes. | [diffable-data-source](references/diffable-data-source.md) |
| List composition — heterogeneous cells, row/item controllers, section controllers, pagination seam, dispatch contract. Includes sectionHeaderTopPadding and sticky-header gotchas. | [list-composition](references/list-composition.md) |
| Screen composition / composer. Programmatic controller instantiation, dependency wiring, navigation closures, scene root composition, idempotent bootstrap for recreated detail controllers. | [composer](references/composer.md) |
| UISplitViewController on iOS 26. The primary column floats as an overlay over a full-width secondary — layout pinning, push-transition host wrapper, and detail-swap fixes. Read before any iPad master-detail work targeting iOS 26. | [split-view-controller](references/split-view-controller.md) |
| iOS 26 behavior changes catalog. Consolidated index of iOS 18 → 26 deltas with links to the deep references, what did NOT change, and the diagnostic workflow for suspected regressions. | [ios-26-behavior-changes](references/ios-26-behavior-changes.md) |
| Image resizing. API decision matrix (renderer vs thumbnail vs ImageIO downsampling), display vs encode paths, template icon sizing. | [image-resizing](references/image-resizing.md) |
| Photo picker. PHPickerViewController vs deprecated UIImagePickerController (library mode is ~2× slower to present, every time), camera-mode exception, background-queue delegate callback, load-failure vs remove-image contract. | [photo-picker](references/photo-picker.md) |
| Self-sizing — measuring one view's natural size: systemLayoutSizeFitting, generic modal/sheet/popover preferredContentSize, self-sizing cells, complete constraint chains, auto-resize-on-layout-pass trap. NOT for container height during animated multi-step child swaps (→ step-transition-sizing) nor lightweight tooltip popovers with arrow/safe-area chrome (→ popover-tooltip). | [self-sizing](references/self-sizing.md) |
| Step transition sizing — wizard / multi-step card swapping children of different heights: explicit container height + measurement + snapshot-and-reparent of the outgoing child. NOT for single-view height animation (→ animation.md) nor modal/popover sizing (→ self-sizing.md). | [step-transition-sizing](references/step-transition-sizing.md) |
| Vertical alignment. centerY vs baseline decision, manual-frame container limitations, measuring real control heights instead of arithmetic. | [alignment](references/alignment.md) |
| UIButton.Configuration. Configuration vs legacy API are mutually exclusive rendering paths; titleTextAttributesTransformer, silent override trap. | [uibutton-configuration](references/uibutton-configuration.md) |
| UIButton icon badge — small circular icon overlay. `.custom` type + icon as subview, manual highlight. | [uibutton-icon-badge](references/uibutton-icon-badge.md) |
| View wrapping. `wrapped(insets:)` container padding, section decoration helpers, when to use vs a manual wrapper. | [view-wrapping](references/view-wrapping.md) |
| Content overflow detection. Two-pass layout — show everything, then measure actual wrap; never estimate widths. NOT for making labels wrap correctly (→ label-wrapping). | [overflow-detection](references/overflow-detection.md) |
| Multiline label wrapping in stacks. Icon-row rule (hugging alone lets the icon be crushed to zero), stale wrap height under width churn, self-syncing preferredMaxLayoutWidth label. NOT for detecting overflow (→ overflow-detection) nor container sizing (→ self-sizing). | [label-wrapping](references/label-wrapping.md) |
| Shadow and clipping. Ancestor clipsToBounds chain, shadow + cornerRadius parent/child split, layer frame ownership, layer border drawing above sublayers (floating badge strike-through), UILabel background trap, iOS 26 sheet color seam. | [shadow-and-clipping](references/shadow-and-clipping.md) |
| Keyboard avoidance. Scroll-view inset adjustment via keyboardWillChangeFrame, animation sync, inputView handling, first-responder scrolling, and the background-tap dismisser rule (a tap-to-dismiss recognizer that fires on control taps silently swallows the tap). | [keyboard-avoidance](references/keyboard-avoidance.md) |
| Menu vs popover decision. UIMenu for flat select-and-dismiss option lists; UIPopover only for custom UI or multi-step interaction. | [menu-vs-popover](references/menu-vs-popover.md) |
| Popover tooltip. Safe-area centering trap, iPhone adaptation, preferredContentSize calculation, arrow direction, tap targets. | [popover-tooltip](references/popover-tooltip.md) |
| Localizable.strings escapes. Only capital `\Uxxxx` works; lowercase `\u` silently becomes literal text — prefer direct UTF-8 characters. | [localizable-strings-escapes](references/localizable-strings-escapes.md) |
| Localization bundle discovery. Framework-only `.lproj` hides the Settings language picker; declare `CFBundleLocalizations` + `CFBundleAllowMixedLocalizations` in the app's Info.plist. | [localization-bundle-discovery](references/localization-bundle-discovery.md) |
| Auto Layout spacing and distribution. setCustomSpacing, why CSS-flex spacers don't translate, independent top/bottom pinning, flexible gap strategies. | [autolayout-spacing](references/autolayout-spacing.md) |
| Navigation bar appearance. Appearance slots, iOS 26 backgroundColor breaking change, large-title scroll tracking. On iOS 26, custom search-field tint requires leaving UISearchController. | [navigation-bar-appearance](references/navigation-bar-appearance.md) |
| Testing principles — the what/why layer: test levels, async spy design, assertion strategy, memory leak tracking. Framework-agnostic; pair with testing.md for UIKit mechanics. | [testing-principles](references/testing-principles.md) |
| UIKit testing — the how layer: lifecycle simulation, semantic list helpers, reuse/visibility tests, pagination integration tests, window-hosted frame-level layout tests. Pair with testing-principles.md for level and assertion decisions. | [testing](references/testing.md) |
| Eliminating objc_setAssociatedObject. UIAction closures, subclass stored properties, wrapper views — plus the downstream traps each replacement introduces. | [associated-objects](references/associated-objects.md) |
| UIViewRepresentable bridge. Two golden rules (defer UIKit→SwiftUI state async; diff instead of reset in updateUIView), coordinator callbacks, pre-rendered bitmaps, Swift 6 delegate isolation. | [uiview-representable](references/uiview-representable.md) |
| iCloud ubiquity container. NSMetadataQuery discovery, bulk download with progress-based timeouts, upload-confirmation polling with fresh URLs, Files-app visibility, fresh-install restore. | [icloud-ubiquity](references/icloud-ubiquity.md) |
| Cloud backup providers / OAuth REST (Google Drive, Dropbox). Provider-agnostic backup architecture — user-visible storage, OAuth scope re-consent, atomic pointer publish, restore-integrity hardening, transfer-session configuration, remote-status display (list authority, stale-while-revalidate, display cache), advisory contents manifest. Read before building any cloud backup/restore feature. | [cloud-backup-providers](references/cloud-backup-providers.md) |

### Xcode / Project Setup

| Topic | Reference |
|-------|-----------|
| Xcode project setup. Workspace layout, synced folders, SPM deps, cross-project refs, app identity, shared schemes, gotcha checklist. | [xcode-project-setup](references/xcode-project-setup.md) |
| xcconfig hierarchy. Naming convention, inline vs xcconfig split, target-level keys, the Tuist `.recommended` SWIFT_VERSION shadowing trap, Xcode upgrade SOP. | [xcconfig](references/xcconfig.md) |
| Build phase scripts. SwiftFormat pre-commit hook, SwiftLint pre-build, Crashlytics dSYM upload (all-dSYMs directory rule, Debug collection gating), script sandboxing. | [build-phases](references/build-phases.md) |
| Makefile. Design principles, simulator destination, run target, warnings target, adaptation checklist. | [makefile](references/makefile.md) |
| Makefile template. | [Makefile.template](references/Makefile.template) |
| Tuist SPM integration. Xcode-native vs XcodeProj-based, wrapper target problem, migration steps. | [tuist-spm-integration](references/tuist-spm-integration.md) |
| xcodebuild error detection. Dual failure detection (exit code + BUILD FAILED grep), test crash detection, CODE_SIGNING_ALLOWED=NO. | [xcodebuild-error-detection](references/xcodebuild-error-detection.md) |
| CLI distribution signing. exportArchive cloud signing needs an Xcode-accounts OAuth session, not an ASC API key; do not mint local distribution certs as a workaround. | [cli-distribution-signing](references/cli-distribution-signing.md) |

### Swift Coding Style (App Context)

| Topic | Reference |
|-------|-----------|
| Swift conventions. Opaque vs existential types, type design, protocols, error handling, API design, file organization. | [swift-style](references/swift-style.md) |
