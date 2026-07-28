# Changelog

## [Unreleased]

- Documented the animated-reconfigure trap in `diffable-data-source` — an animated `apply` carries structural changes only; `reconfigureItems` rides a second, non-animated apply, because a cellProvider running inside the animation transaction can leave a `UIStackView` arranged subview's hide / unhide half-applied (`view.isHidden == true` → out of layout at `x = -width` and out of the accessibility tree, while `layer.isHidden == false` keeps painting). Includes the pixels-present / AX-element-absent diagnostic, the lldb flag comparison, why the cell-side `performWithoutAnimation` "fix" is wrong, and why the pin belongs in UI automation rather than a unit test. Corrected the Common Mistakes row that previously prescribed folding `reconfigureItems` into the same apply; `list-composition` → "First-Apply Animation Gate" now points at it.

## [0.9.0] — 2026-07-17

- Added `label-wrapping` reference — multiline label wrapping in stack views: icon-row rule (hugging alone lets the icon be crushed to zero; require horizontal compression resistance too), stale wrap height under width churn fixed by a self-syncing `preferredMaxLayoutWidth` label with placement rationale, symptom→cause table; Topic Router row carries NOT-for boundaries against `overflow-detection` and `self-sizing`.
- Documented layer border z-order in `shadow-and-clipping` — `layer.borderWidth` composites above every sublayer, striking through overlapping subviews (floating badge, corner close button); fix is a dedicated border subview ordered below the overlapping subview.
- Documented frame-level layout tests in `testing` — host views in a real `UIWindow` (bare containers silently keep stale frames after constraint changes); harness fidelity does not reproduce production multi-pass width-churn bugs, so treat such tests as smoke-level invariants and always test-the-test against pre-fix code.

## [0.8.0] — 2026-07-08

- Added `photo-picker` reference — `PHPickerViewController` vs deprecated `UIImagePickerController` library mode (~2× slower to present, every time, and requires photo permission PHPicker doesn't need), camera-mode exception, background-queue delegate callback trap, load-failure vs remove-image contract.
- Disambiguated overlapping Topic Router row families — animation (`animation` / `implicit-animations` / `compound-cell-row-animation`), testing (`testing-principles` / `testing`), sizing (`self-sizing` / `step-transition-sizing` / `popover-tooltip`): each row now carries a scope discriminator and NOT-for cross-pointers; added a family rule requiring boundary declarations on both parent and child rows.
- Expanded `cloud-backup-providers` — remote-status display (list authority, stale-while-revalidate, display cache), advisory contents manifest, cache invalidation and manifest stale-drop honoring list authority and upload failure.
- Documented `composer` idempotent bootstrap rule for recreated detail controllers.
- Documented signing rules for installable builds — `makefile` run-installed builds must stay signed (keychain `-34018`), and `xcodebuild-error-detection` `CODE_SIGNING_ALLOWED=NO` must never touch installable builds.

## [0.7.0] — 2026-07-05

- Added `diffable-data-source` reference — diffable as the default data source, `Hashable`-not-`Identifiable` constraint, two Apple-blessed identifier patterns, `reconfigureItems` vs `reloadItems` vs `apply`, iOS 15 `animatingDifferences` semantic change, Swift 6 `Sendable` section/item identifier patterns, iPadOS cell focus-halo migration trap.
- Added `cloud-backup-providers` reference — provider-agnostic backup architecture for Google Drive / Dropbox / iCloud: user-visible storage as the iron law, OAuth scope-expansion 403 re-consent, atomic pointer publish with millisecond version ids, pointer namespaces for breaking bundle formats, storage-location migration hook, restore-integrity hardening, dedicated ephemeral transfer session with URLCache disabled, bounded POST retry, upload stall detection.
- Rewrote the skill as a forward-looking guidance manual:
  - Fixed factual error — `UITableView.CellRegistration` does not exist; documented the UITableView generic-helper alternative.
  - Resolved internal contradictions — animation tier table legitimizes spring for choreography; MARK rules aligned between `swift-style` and `file-structure`; `AnyHashable` inline conformance verified compiling on Swift 6.3 and the old warning demoted to an older-toolchain fallback.
  - Converted war-story narratives to design rules with mechanisms; genericized private project symbols and dead links.
  - Slimmed Topic Router rows to ≤2 sentences; deduplicated the iOS 26 version table and bind-before-load trap to canonical homes.
  - Added generation checklists to `animation`, `swift-style`, `composer`, `file-structure`, `split-view-controller`.
  - Expanded the mockup loop into a universal UI Verification Definition of Done; added a precedence conflict table; replaced Instruments steps with agent-executable diagnostics.
  - Rewrote `diffable-data-source` in English.
- Documented iOS 26 `UISearchController` prescription — custom search-field tint requires hosting a custom search pill in the root view.
- Documented Tuist `.recommended` `defaultSettings` injecting target-level `SWIFT_VERSION = 5.0` that silently shadows project-xcconfig Swift 6, with the `recommended(excluding:)` fix.
- Added `systematic-debugging` cross-trigger and screenshot-evidence verification loop to SKILL.md.

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
