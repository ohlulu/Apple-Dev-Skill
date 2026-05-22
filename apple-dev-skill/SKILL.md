---
name: apple-dev-skill
description: >-
  Apple platform development: UIKit patterns, SwiftUI bridging, Xcode/Tuist
  project setup, xcconfig, build phases, Makefile, and Swift coding conventions
  for app development. Load whenever working in an Apple app codebase — building
  features, fixing bugs, debugging layout or build issues, implementing designs,
  adjusting animations, writing tests, setting up project structure, or reviewing
  Swift code in an app context. Also load for objc_setAssociatedObject, UIViewRepresentable
  bridging, iCloud ubiquity containers, Tuist project generation, xcconfig hierarchy,
  or build phase scripts.
  NOT for: server-side Swift (Vapor), Linux Swift, CLI tools, or platform-agnostic
  SPM libraries — those rely on global rules.
  Trigger words: "UIKit", "UIViewController", "UIView", "UITableView",
  "UICollectionView", "Auto Layout", "Xcode", "xcconfig", "build phase",
  "Tuist", "Makefile", "SwiftUI bridge", "UIViewRepresentable",
  "Swift style", "type design", "protocol", "error handling",
  "專案設定", "建置設定", "建置腳本", "iOS", "app development".
---

# Apple Dev Skill

Unified reference for Apple platform app development — UIKit/UI patterns, Xcode project setup, and Swift coding conventions scoped to app contexts.

## Precedence Rule

When a project already has a clear, established local convention, follow it by default.
Ask the user only when local conventions are ambiguous, conflicting, or likely harmful.
Do not silently replace a strong project convention with this skill's defaults.

## Topic Router

Consult the reference file for each topic relevant to the current task. Apply all rules from the matched references — do not skip them for convenience.

### UIKit / UI Patterns

| Topic | Reference |
|-------|-----------|
| File structure (property ordering, extensions, layout placement for UIViewController, UIView, UITableViewCell, and other UIKit subclasses) | [file-structure](references/file-structure.md) |
| Animation (duration, curve, fade defaults, expand/collapse choreography, stagger reveal, custom layout view height animation pitfalls) | [animation](references/animation.md) |
| Compound cell row animation (animating row insert/remove in a settings-style compound card cell, UISwitch distortion trap, performBatchUpdates vs invalidateLayout in compositional layout, UIStackView isHidden animation) | [compound-cell-row-animation](references/compound-cell-row-animation.md) |
| Cell registration (CellRegistration vs legacy register/dequeue, pitfalls, handler lifecycle, retain cycles, dynamic cell types) | [cell-registration](references/cell-registration.md) |
| List composition (heterogeneous cells, row/item controllers, section controllers, load-more controller, pagination seam, diffable, compositional layout, default shapes, sectionHeaderTopPadding gotcha, sticky header bleed layers) | [list-composition](references/list-composition.md) |
| Screen composition / composer (programmatic controller instantiation, dependency wiring, navigation closures, scene root composition) | [composer](references/composer.md) |
| Image resizing (UIGraphicsImageRenderer, preparingThumbnail, CGImageSource downsampling, template icon sizing, display vs encode) | [image-resizing](references/image-resizing.md) |
| Self-sizing (systemLayoutSizeFitting, preferredContentSize, self-sizing cells, complete constraint chains) | [self-sizing](references/self-sizing.md) |
| Vertical alignment (centerY vs baseline, mixed-size text, manual-frame containers, measuring real button height) | [alignment](references/alignment.md) |
| UIButton.Configuration (Configuration vs legacy API, titleTextAttributesTransformer, silent override trap) | [uibutton-configuration](references/uibutton-configuration.md) |
| UIButton icon badge (small circular icon overlay, .custom type, icon as subview not setImage, highlight via touchDown/Up) | [uibutton-icon-badge](references/uibutton-icon-badge.md) |
| View wrapping (wrapped(insets:), container padding, section decoration helpers, when to use vs manual wrapper) | [view-wrapping](references/view-wrapping.md) |
| Content overflow detection (two-pass layout, actual vs estimated measurement, dynamic collapse/expand triggers) | [overflow-detection](references/overflow-detection.md) |
| Shadow and clipping (CALayer shadow visibility, contentView.clipsToBounds default, ancestor chain check, deferred visual initialization, UILabel backgroundColor not clipped by cornerRadius, iOS 26 sheet double-background color shift) | [shadow-and-clipping](references/shadow-and-clipping.md) |
| Keyboard avoidance (scroll view inset adjustment, keyboardWillChangeFrame, animation sync, inputView handling, first responder scrolling) | [keyboard-avoidance](references/keyboard-avoidance.md) |
| Menu vs popover (UIMenu for flat option selection, UIPopover for custom UI, decision rule, sizing pitfalls, migration guide) | [menu-vs-popover](references/menu-vs-popover.md) |
| Popover tooltip (UIPopoverPresentationController safe-area centering trap, iPhone adaptation, preferredContentSize calculation, arrow direction, tap target sizing, dismiss behavior) | [popover-tooltip](references/popover-tooltip.md) |
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

### Swift Coding Style (App Context)

| Topic | Reference |
|-------|-----------|
| Swift conventions (opaque vs existential types, type design, protocols, error handling, API design, file organization) | [swift-style](references/swift-style.md) |
