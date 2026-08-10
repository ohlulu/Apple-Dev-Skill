# Changelog

## [Unreleased]

- Added `modular-architecture` reference — an operational guide (not a pattern catalog) for modularizing an app: a gate against premature splitting (single-module is correct until team growth or concrete symptoms), the five-layer target blueprint (App→Features→Workflows→Services→Core) with two compiler-enforceable iron rules (same-layer modules never import each other; constructor injection wired at the App root makes cycles uncompilable), a four-question placement procedure whose no-instant-hit outcome is "stop and re-examine the taxonomy" rather than shoehorn, and recipes for the two canonical feature-module failures — shared business logic (extract a Services module, lift cross-service flows into Workflows; never a Shared grab-bag) and cross-feature screen reuse (thin API module with a screen factory protocol; the one-off shim protocol + `AnyView` bridge is the anti-pattern it replaces). Also covers leaf-first monolith migration order, an anti-pattern recognition table, and the static/dynamic/mergeable linkage decision with the profile-don't-dogma rule (dynamic maps wholesale in pre-main and skips dead-code stripping, so it can be bigger than static — observed 200 kB dynamic vs 15 kB static for the same dependency). Distilled from Jacob Bartlett's modular-architecture series and the RevenueCat SDK's layering.

## [0.10.0] — 2026-08-09

- Documented the background-tap dismisser rule in `keyboard-avoidance` — a root-view tap-to-dismiss recognizer needs a second guard beyond `cancelsTouchesInView = false`: it must refuse touches landing on a `UIControl`. The gesture's action runs before the delayed `touchesEnded` reaches the control, so `endEditing`'s layout pass writes the control's new frame to the **model** layer and `UIControl.endTracking` then resolves the touch-up as `.touchUpOutside` — the tap is silently swallowed and the user has to tap the button twice, more reliably the bigger the keyboard-driven shift. Includes the `shouldReceive` predicate walking the superview chain, why deferring the dismissal couples correctness to run-loop ordering, and why the predicate belongs in a testable static function.
- Documented the animated-reconfigure trap in `diffable-data-source` — an animated `apply` carries structural changes only; `reconfigureItems` rides a second, non-animated apply, because a cellProvider running inside the animation transaction can leave a `UIStackView` arranged subview's hide / unhide half-applied (`view.isHidden == true` → out of layout at `x = -width` and out of the accessibility tree, while `layer.isHidden == false` keeps painting). Includes the pixels-present / AX-element-absent diagnostic, the lldb flag comparison, why the cell-side `performWithoutAnimation` "fix" is wrong, and why the pin belongs in UI automation rather than a unit test. Corrected the Common Mistakes row that previously prescribed folding `reconfigureItems` into the same apply; `list-composition` → "First-Apply Animation Gate" now points at it.
- Fixed Crashlytics dSYM guidance in `build-phases` that taught the single-dSYM trap — the section recommended `upload-symbols --build-phase` and explicitly said not to pass dSYM paths manually, but that mode resolves only `${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}` and ignores every other dSYM in the folder (verified empirically against upload-symbols 3.21). Every dynamic dependency produces its own dSYM, and in a Composition-Root layout those frameworks hold nearly all real code — so a project following the guide uploaded almost nothing and earned guaranteed missing-dSYM console warnings once real crashes arrived. Pass the whole `DWARF_DSYM_FOLDER_PATH` directory instead: directory arguments are searched recursively, covering app + framework dSYMs in one call. The sample now fails the archive when the tool is missing rather than warning (the old fallback contradicted the file's own principle #3), and gates collection off in Debug via `FirebaseCrashlyticsCollectionEnabled`, since Debug builds produce no dSYM at all and their crashes are permanently unsymbolicatable console noise.
- Added `animated-image-playback` reference — traps for a `UIImageView` subclass that drives its own frame engine (SDWebImage's `SDAnimatedImagePlayer`, or CADisplayLink + frame buffer). Overriding `isAnimating` freezes the subclass's own rendering: UIKit's image-display path consults it first and early-returns before `_setImageViewContents:`, so every `super.image = frame` updates the model value only and the screen holds the first frame forever. `SDAnimatedImageView` gets away with the override solely because it renders through `displayLayer:` — the override and the rendering path are a load-bearing pair, and copying the API surface without the rendering half ships the freeze. Also covers the visibility-pause freeze (UICollectionView pools offscreen cells by setting `hidden` in place, so no descendant hook fires on scroll-back) with a `.common`-mode watchdog resume, and a four-step probe ladder whose layer-property toggle is the discriminator that turns "frames delivered but screen frozen" into one specific UIKit code path.
- Rewrote `makefile` around the decisions a Makefile author actually faces, not just a target list. New: recipe-vs-script split with a concrete threshold (~10 lines, loops, AppleScript, CI reuse) and the reason it matters (`$$` escaping, no shellcheck, no `sh -x`, no standalone run); simulator-vs-physical-device targeting; DerivedData strategy as an explicit trade-off table, including that sharing the IDE cache forbids `-skipMacroValidation` and `CODE_SIGNING_ALLOWED=NO` because they change the build-settings fingerprint and force full rebuilds; streaming output via `tee` + `grep --line-buffered` under `set -o pipefail`, and why `xcbeautify --quieter` swallows errors that share a task with a warning; parameterised targets (`ONLY=`, `CONFIG=`) instead of a target per scope.
- Hardened build-result verification across `makefile` and `xcodebuild-error-detection` — green now requires exit 0 **and** the success marker present **and** no crash marker. Checking only for `BUILD FAILED` passes a build that died before compiling anything (missing scheme, locked DerivedData), since such a log carries no failure line either. Dropped bare `crashed` from the crash pattern: the host app's own runtime logging shares the stream and reddens every noisy run. Logs are now named after the working directory so sibling git worktrees stop clobbering each other's results.
- Replaced `simctl install booted` in `makefile` with explicit UDID resolution — `booted` picks whichever simulator happens to be up, so an iPhone sim from another project makes an iPad-only app fail to install with an error naming the app rather than the device. `SIM_NAME`/`SIM_OS` now feed both the destination string and a runtime-scoped awk lookup, so a same-named device under another runtime cannot win. Boot via `simctl bootstatus -b`, which waits for readiness; plain `boot` returns early and installs in that window fail intermittently.
- Documented physical-device workflows in `makefile` — sourceable selection script with `DEVICE_UDID=` override, gitignored cache treating a disconnected device as a miss, and live `xctrace` probe. **A selection script must never `read` without a TTY**: agents and CI have none, so gate prompts on `[ -t 0 ]`, auto-select when unambiguous, and otherwise fail with the candidate list and the command to pick one. Also covers `devicectl` install/launch, `-allowProvisioningUpdates`, and stating a project's no-simulator constraint (device-only binary slices) in the Makefile header.
- Added `xcode-close.applescript` — closes only this repo's Xcode workspace windows before `tuist generate`. Matches by **file path, not window title**: a title prefix also closes `MyAppTweak` when regenerating `MyApp`, and cannot tell two checkouts of one repo apart. Carries the two Xcode-scripting constraints: `repeat with d in (get documents)` yields a nested specifier Xcode resolves wrongly (distinct workspaces all report the same `file`), and `documents` is z-ordered so closing shifts later indices — index explicitly and iterate backwards.
- Rewrote `Makefile.template` to match: verification-carrying `xc` macro, UDID-resolving `run`, parameterised `test`, DerivedData strategy switch documented inline, and both version sources (xcconfig / Project.swift) kept as alternatives.
- Fixed IDE DerivedData resolution in `makefile`, `Makefile.template`, and `xcode-project-setup` — the `warnings` target matched `-name '<project>-*' | head -1`, but the directory suffix hashes the workspace's *absolute path*, so a stale entry accumulates for every location the project has occupied (git worktrees, a `/tmp` clone for a baseline comparison, a moved repo). A real machine had four `DingPOS-*` directories, two pointing at `/tmp` checkouts; `head -1` returns whichever the filesystem lists first, so the target could silently clean-build a different checkout and report its warnings. Now matches each candidate's recorded `WorkspacePath` from `info.plist`, which is deterministic and degrades to empty for the existing guard.
- Resolved a contradiction in `xcode-project-setup`'s DerivedData gotcha row, which prescribed pointing `-derivedDataPath` at "the same location Xcode GUI uses (e.g. project-local `.derivedData/`)" — two different locations. The actual failure is CLI and IDE *disagreeing*; the fix is to apply one strategy consistently, so the row now points at the new trade-off section. `xcode-project-setup` § Warning Detection also notes that shared-cache projects need no `warnings` target at all.
- **Corrected the `CODE_SIGNING_ALLOWED=NO` mechanism** in `makefile`, `Makefile.template`, and `xcodebuild-error-detection`. The previous text said the flag "strips the `application-identifier` entitlement". Measured across three separate apps: simulator builds carry an **empty entitlements dictionary either way**, so that was never the distinguishing factor. What the flag actually does is skip the `CodeSign` build phase, leaving only the linker's ad-hoc signature — `codesign -dvvv` reports `flags=0x20002(adhoc,linker-signed)` with it versus `flags=0x2(adhoc)` without — and simulator securityd rejects Keychain calls from a linker-signed-only binary with `-34018`. The conclusion (never on an installable build) was right; the stated mechanism was wrong, and it pointed anyone diagnosing the bug at an entitlement that is legitimately absent. Also extended the rule to test targets, whose bundle is installed too, and added that the flag must be consistent across every script sharing one DerivedData path.
- Fixed a live bug in the shipped `Makefile.template` `help` target — the awk's final clause `!/^##/{d=""}` cleared the pending description on *any* non-`##` line, so the ordinary shape of a `##` doc line, then a `#` comment explaining the why, then the target, dropped that target from the menu. The template's own `clean` target was invisible in `make help` because of it. Added `/^#/{next}` and documented it as the third awk trap alongside the colon strip and the multi-target regex. Failure mode is nasty because the target still works — it is only missing from the menu.
- Sharpened the crash pattern in `makefile` and `xcodebuild-error-detection` — a bare `SIGABRT` is not safe either. Firebase Crashlytics prints `The signal SIGABRT has a non-Crashlytics handler` on every green run, so the pattern reddened whole passing suites. Anchor to how a crash is *reported* (`Restarting after unexpected exit|Crashed:|due to (signal )?(SIGABRT|SIGSEGV)|terminated due to`) and grep a known-passing log before widening it.

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
