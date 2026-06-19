# iOS 26 Behavior Changes — Catalog

Behavior deltas between iOS 18 and iOS 26 (.0 / .1 / .2 / .4) that
this codebase has tripped on. Each entry links to the deeper
reference where it's discussed; this file is the consolidated index.

iOS 25 was never released — Apple jumped from iOS 18 (2024) to iOS 26
(2025) to align version numbers with the year. The previous baseline
is iOS 18.

## UISplitViewController

### Sidebar Floats Above Content (Liquid Glass)

**iOS 26.0+** — the primary sidebar is rendered with a Liquid Glass
material and *floats* above the secondary instead of sitting flush
against it.

Consequences:

- Detail content anchored to `view.leadingAnchor` draws *under* the
  sidebar overlay
- `primaryBackgroundStyle = .none` no longer removes the sidebar
  background — the Liquid Glass effect is composited at a deeper
  level. Use `primaryBackgroundEffect = nil` instead.
- `preferredSplitBehavior = .tile` is ignored

**Fix**: pin detail content to `safeAreaLayoutGuide.leadingAnchor`
(the sidebar appears as a leading safe-area inset). See
`split-view-controller.md` → "iOS 26 Behavior Change — Primary
Column Is an Overlay".

**Temporary opt-out**: `UIDesignRequiresCompatibility = YES` in
Info.plist restores the iOS 18 sidebar look. Apple has said this
property will be removed in future releases, so treat as a stopgap
only.

### setViewController(_:for:) Adds VC View with `.zero` Frame

**iOS 26.0–26.4 (current)** — the container's add-child sequence
does not propagate the final bounds + safe-area insets to the
incoming VC's view *before* the appearance transition begins. Auto
Layout resolves the real values inside the transition window, and
every sub-element appears to animate from origin.

Visible as: gradient banner crossfade, segmented-control pill
"slide", switch thumb "settle", labels "fade in". These are
intermediate frames of the same layout resolve, not separate
animations.

**Fix**: call `viewController.view.layoutIfNeeded()` *after*
`setViewController` returns. See `split-view-controller.md` →
"Detail Swap Settling Animation on iOS 26" for the wrapper
implementation.

### pushViewController(_:animated:) Same Layout Regression

**iOS 26.0–26.1**: same `.zero`-frame issue as above, manifested
during navigation push transitions.

**iOS 26.2**: Apple shipped a partial fix.
(https://darjeelingsteve.com/articles/Fixing-UINavigationController-Push-Animation-Layout-Issues-on-iOS-26.html)

**iOS 26.4**: still good for the push path. Apply the same
`viewController.view.layoutIfNeeded()` after push if a regression
re-appears.

### Push Transition Slides Across Full Width

**iOS 26.0+** — when the secondary column hosts a
`UINavigationController`, animated `pushViewController` inside it
slides the new VC across the *entire* split width and lands at
`x=0`, hidden under the primary sidebar overlay.

**Fix**: wrap the secondary nav in a host VC (`SecondaryColumnHost`)
that pins it to `safeAreaLayoutGuide.leadingAnchor`. See
`split-view-controller.md` → "Fix — Host VC Wrapper".

## UISearchController

### Custom Tint on Nav-Bar-Hosted Search Field Is Not Supported

**iOS 26.0+** — the inner search-field capsule of a `UISearchBar`
hosted by `navigationItem.searchController` is rendered as Liquid
Glass material and re-composited on every layout pass. App-side
tinting (`searchTextField.backgroundColor`, `setSearchFieldBackgroundImage`,
appearance proxy) is silently overridden. There is no per-control
tint API in the iOS 26 SDK; WWDC25 direction is "do not paint over
the material."

The override fires reliably when the screen also carries another
pinned chrome element (collection-view scope bar, filter chips).
Screens with only the search bar may *appear* to tint successfully
until layout invalidates — do not rely on it.

**Fix**: if a custom fill is required, abandon `navigationItem.searchController`
for that screen and host a custom search-pill field in the root view
above the list. Wire its text-change callback to whatever
`UISearchResultsUpdating` was driving. See
`navigation-bar-appearance.md` → "iOS 26 — Custom Search Bar Tint
Requires Abandoning UISearchController" for the full recipe and the
trade-offs that come with it (results-controller plumbing, dimming,
sidebar integration). Decide once at the architecture level: one
custom search-pill component, every list surface.

**Anti-fixes**: do NOT stack `setSearchFieldBackgroundImage` over the
proxy override over `searchTextField.backgroundColor`. None of them
win, and the image variant strips the rounded capsule chrome when
`capInsets` aren't perfect, producing worse output than the grey
default.

**App-wide opt-out**: `UIDesignRequiresCompatibility = YES` in
`Info.plist` reverts the entire app to iOS 18 visuals (transitional;
Apple documents it will be removed). Use only if Liquid Glass is
breaking the whole design system, not for a single search bar.

## Animation Behavior

### Detail Swap Looks Animated (No API Changed)

**iOS 26.0+** — same root cause as the layout regression above. The
swap *call* hasn't changed; the *effect* looks animated because of
the `.zero`-frame layout resolve.

See `implicit-animations.md` → "Sub-Layer Resolution Artifacts
(iOS 26 regression)" for the diagnostic flow.

## What Did NOT Change

For honesty, these were assumed to be iOS 26 changes during this
session's debugging but are actually pre-existing UIKit behavior
that the team simply noticed for the first time:

- `CAGradientLayer.colors` implicit crossfade — iOS 7+
- `UISegmentedControl.selectedSegmentIndex` setter animates the pill
  on delta change — iOS 13+
- `UISwitch.isOn` setter animates the thumb — iOS 6+
- `UITableViewDiffableDataSource.apply(_:animatingDifferences:)`
  animates every row when applying from an empty source — pre-iOS
  26

See `implicit-animations.md` for the full catalog and disable-at-
source recipes.

## Diagnostic Workflow

When you suspect an iOS 26 regression:

1. **Reproduce on the current simulator runtime** — `xcrun simctl
   list runtimes` to confirm version. The two we encounter:
   `iOS-26-2` (23C54) and `iOS-26-4` (23E244).
2. **Web research with the exact API name** — e.g. "iOS 26
   UISplitViewController setViewController animation". Apple
   Developer forums and Stack Overflow have hit most of these.
3. **Check darjeelingsteve.com / blog posts dated 2025-09 to 2025-12**
   — high signal source for iOS 26 UIKit regressions.
4. **Apple release notes** — `https://developer.apple.com/documentation/ios-ipados-release-notes/`
   for the relevant point release. Often confirms a regression by
   listing the *fix* in a later release.
5. **If installing iOS 18 sim runtime is feasible** — `xcodebuild
   -downloadPlatform iOS` or via Xcode → Settings → Components.
   ~7GB / ~30 min. Provides a real A/B test.

## Reference Implementations

Code in DingPOS that adopts the iOS 26 fixes:

- `DingKit/Sources/DingKitiOS/Navigation/UISplitViewController+Affordances.swift`
  — `setViewControllerWithoutAnimation` wrapper with the
  `layoutIfNeeded` fix
- `DingKit/Sources/DingKitiOS/Navigation/SecondaryColumnHost.swift`
  — host wrapper for animated push inside secondary
- `DingKit/Sources/DingKitiOS/SubscriptionFeature/SubscriptionViewController.swift`
  → `GradientStatusCardView.init` — layer-actions suppression on the
  gradient
- `DingKit/Sources/DingKitiOS/SubscriptionFeature/SubscriptionViewController.swift`
  → `viewDidLoad` calls `applyState()` before async load —
  mount-state seeding
- `App/Sources/Composers/SettingsComposer.swift` — VM pre-warm
  pattern for subscription status
