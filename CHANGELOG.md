# Changelog

## [0.6.0] — 2026-06-09

- **Breaking**: Renamed skill from `uikit-expert-skill` to `apple-dev-skill`.
- **Breaking**: Renamed GitHub repo from `UIKit-Expert-Skill` to `Apple-Dev-Skill`.
- Merged `xcode-skill` (Xcode/Tuist project setup, xcconfig, build phases, Makefile, shared schemes, gotchas) into this skill.
- Merged `swift-coding-style` (type design, protocols, error handling, API design, file organization) into this skill.
- Added Topic Router sections for Xcode/Project Setup and Swift Coding Style.
- Added 8 new reference files: xcode-project-setup, xcconfig, build-phases, makefile, Makefile.template, tuist-spm-integration, xcodebuild-error-detection, swift-style.
- Added `zoomable-image-preview` reference — tap-to-enlarge avatar / image viewer (IG / Photos.app / Telegram style): `.overFullScreen` not `.custom` for blur backdrop; UIScrollView zoom-target centring via `bounds.size =` + symmetric `contentInset` + explicit `contentOffset` snap; `frame =` under non-identity transform inflates `bounds`; circular `cornerRadius` scales with zoom; hero snapshot in `transitionContext.containerView` coords with `alpha = 0` source hiding; manual pan-to-dismiss (not `UIPercentDrivenInteractiveTransition`) for multi-axis follow-finger feel; `shouldRecognizeSimultaneouslyWith` + lenient `shouldBegin` for scroll-view coexistence; panSnapshot identity re-entry guard; third-party VC self-set `transitioningDelegate` trap (TOCropViewController #486); JPEG storage of circular crops produces white corners that the preview must re-mask.
- Added `Contracts + Wiring` section to `zoomable-image-preview` — piece contracts (HeroSource alpha semantics + 3-place restore, PreviewVC strong-holds delegate, snapshot lives in view not window), ownership graph (UIKit weak → delegate trap), pan handler state-by-state contract (must do / must not do), 7-point acceptance checklist (initial centring, pinch round-trip, cancel pan, commit drag, commit flick, close button, source restoration after 5×).
- Added `step-transition-sizing` reference.
- Added `cli-distribution-signing` reference.
- Added `localization-bundle-discovery` and `localizable-strings-escapes` references.
- Documented iOS 26 implicit-animation traps across `split-view-controller` (push-transition + secondary-swap suppression, three-layer audit, bind-before-load sync-fire) and `apple-dev-skill` Topic Router; nav-bar split appearance + UISearchBar background + sticky header bleed notes.
- Documented `shadow-and-clipping` UILabel `backgroundColor` + `cornerRadius` trap; `popover-tooltip` `systemLayoutSizeFitting` warning; `self-sizing` auto-resize-on-layout-pass trap.
- Documented `icloud-ubiquity` `.current` vs `.downloaded` rule.
- Documented testing async XCTest + task allocator trap and test crash detection.
- Documented `makefile` BUILD FAILED trap, trash-based clean, tuist companions; `build-phases` Crashlytics `-gsp` + `-p ios` requirement.
- Documented `swift-style` struct memberwise-init trap for let-with-default.
- Skill routing description rewritten to trigger by project type, not phrasing.

## [0.4.0] — 2026-05-07

- Added iCloud ubiquity container reference — `startDownloadingUbiquitousItem`, `NSMetadataQuery` discovery, `NSUbiquitousContainers` eager-init gotcha.
- Added popover-tooltip reference — safe-area centering trap.
- Fixed release skill flow to zero-gate after version confirmation.

## [0.3.0] — 2026-05-01

- Added self-sizing reference — `systemLayoutSizeFitting`, `preferredContentSize`, cell auto-dimension.
- Added image-resizing reference — API decision matrix, export gotcha, template icon pattern.
- Added view-wrapping reference — `wrapped(insets:)`, section decoration, decision matrix.
- Added alignment and UIButton.Configuration references.
- Added shadow-and-clipping reference with parent/child split and iOS 26 sheet gotcha.
- Added keyboard-avoidance reference.
- Added overflow detection and expand/collapse animation references.
- Added menu-vs-popover decision reference.
- Added UIButton icon badge reference.
- Added navigation-bar-appearance reference (iOS 26 `backgroundColor` breaking change).
- Added autolayout-spacing reference.
- Added staggered entrance animation pattern for collection view cells.
- Added CALayer frame ownership, transform-safe positioning, and custom layout animation pitfalls.
- Added associated-objects reference — eliminating `objc_setAssociatedObject`.
- Added callback shape rule — avoid closure-of-closures in navigation wiring.
- Added UIViewRepresentable bridge patterns reference.
- Expanded list-composition with dispatch contract, generation checklist, pitfalls, section-level dispatch, stateful sections, and supplementary delegation.
- Added CellRegistration reference — prefer over legacy register/dequeue.
- Added compound-cell-row-animation reference (UISwitch distortion, `performBatchUpdates`, `isHidden` pattern).
- Added project-local release skill.

## [0.2.0] — 2026-04-02

- Relaxed UI property guidance: use direct initialization for one-line setup; reserve `lazy var` closures for multi-statement inline configuration.
- Expanded list composition guidance with a concrete `CellController` identity shape, a fuller `ListViewController` forwarding skeleton, and prefetch forwarding.
- Added visible load-more row guidance with `LoadMoreViewModel`, `LoadMoreCellController`, and a minimal `Paginated<Item>` seam for UIKit pagination consumption.
- Expanded UIKit testing guidance with semantic list helpers, load-more test helpers, pagination integration test flow, and a note on fake refresh controls for deterministic tests.
- Added composer guidance for programmatic screen factories, dependency wiring, navigation closures, and scene root composition.

## [0.1.0] — 2026-03-31

- Added file structure patterns reference for ViewController / UIView organization (extension separation, access level ordering, lazy var UI properties, layout placement).
- Added animation patterns reference (0.1s linear fade default, case-dependent transition durations, no spring unless requested).
- Cleaned up `SKILL.md` for AI-friendliness: operating rules with explicit trigger conditions, single topic router, removed empty placeholders.
- Removed "No Code Formatting or Linting" restriction from `AGENTS.md`.
