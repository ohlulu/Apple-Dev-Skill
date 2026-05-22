# Navigation Bar Appearance

## iOS 26 Breaking Change — backgroundColor Covers Large Title

iOS 26 (Tahoe) restructured `UINavigationBar`'s internal view hierarchy for Liquid Glass. The **background layer is now rendered in front of the large title label**, not behind it.

### Symptom

- Large title visible initially, disappears after scroll and never returns
- Inline (small) title unaffected — it lives in a different layer
- View Hierarchy debugger shows the title label exists behind the background view

### Root Cause

Setting `UINavigationBarAppearance.backgroundColor` (with or without `configureWithOpaqueBackground()`) places an opaque layer on top of the large title. This is a rendering-order change in iOS 26's Liquid Glass architecture. Tracked as FB20986869.

### Fix

```swift
let appearance = UINavigationBarAppearance()

if #available(iOS 26, *) {
    appearance.configureWithTransparentBackground()
    // Do NOT set appearance.backgroundColor — let view.backgroundColor show through
} else {
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = theme.background
}

// These still work on all versions
appearance.shadowColor = .clear
appearance.titleTextAttributes = [.foregroundColor: theme.textPrimary]
appearance.largeTitleTextAttributes = [.foregroundColor: theme.textPrimary]

nav.navigationBar.standardAppearance = appearance
nav.navigationBar.scrollEdgeAppearance = appearance
nav.navigationBar.compactAppearance = appearance
```

The view controller's `view.backgroundColor` is already set to the theme color, so the transparent bar shows the correct background.

### Alternatives

| Approach | Effect |
|----------|--------|
| `configureWithTransparentBackground()` | Fully transparent bar; view's background shows through cleanly |
| `configureWithDefaultBackground()` | System Liquid Glass (frosted) effect; adapts to content behind |
| SwiftUI `.toolbarBackground(_:for:)` | SwiftUI-native; works on iOS 26; not available in pure UIKit |

### Key Constraint

Apple DTS explicitly recommends moving away from `UINavigationBarAppearance.backgroundColor` on iOS 26 (Developer Forums thread/807331). The API is not deprecated, but its behavior is broken for large titles.

## Split Appearance for Opaque Chrome on iOS 26

The iOS 26 large-title cover bug ([FB20986869](#ios-26-breaking-change--backgroundcolor-covers-large-title)) only triggers in the **large-title state** (scroll edge, title expanded). Once the user scrolls and the title collapses to inline, an opaque background is safe.

This lets you have *both* a clean transparent large title and an opaque chrome that stops content from bleeding visibly behind the nav bar when scrolled.

### Pattern

```swift
let edgeAppearance = UINavigationBarAppearance()
edgeAppearance.configureWithTransparentBackground()
edgeAppearance.backgroundColor = nil
edgeAppearance.shadowColor = .clear
// … title attributes …

let scrolledAppearance = UINavigationBarAppearance()
scrolledAppearance.configureWithOpaqueBackground()
scrolledAppearance.backgroundColor = theme.background
scrolledAppearance.shadowColor = .clear  // optional: drop hairline
// … same title attributes …

bar.scrollEdgeAppearance = edgeAppearance     // large title visible
bar.standardAppearance = scrolledAppearance   // title collapsed
bar.compactAppearance = scrolledAppearance
if #available(iOS 15.0, *) {
  bar.compactScrollEdgeAppearance = edgeAppearance
}
```

Apply the **same title attributes** to both appearances so the title font / colour doesn't flash during the transition.

### Alternatives to opaque solid

| Choice | Visual feel | Bleed protection |
|--------|------------|------------------|
| `configureWithOpaqueBackground` + solid colour | Flat, matches mockup-style designs | Complete |
| `configureWithDefaultBackground` | iOS frosted material (Mail/Notes/Files feel) | Blurs but doesn't fully hide |
| `configureWithTransparentBackground` | Flat, content shows through | None |

### When This Pattern Applies

- You want the body background to extend visually into the nav bar at the top of scroll (no chrome strip)
- AND you don't want cells visibly scrolling under the nav bar mid-scroll
- AND you need to preserve the iOS 26 large title

If any of these doesn't apply, use a single appearance (transparent OR opaque OR frosted) across all slots.

## Embedded UISearchBar Has Independent Background

A `UISearchBar` placed via `navigationItem.searchController` is not a child of the navigation bar's appearance pipeline. It lives in its own strip below the title area and renders its background via `searchBar.backgroundImage`, **completely ignoring `UINavigationBarAppearance.backgroundColor`**.

### Symptom

Nav bar background is set to opaque (or frosted), but cell content visibly scrolls *under the search bar* with the search bar's default translucent material. The chrome above and below the search bar is fine; only the search bar's own strip leaks.

### Fix

```swift
let opaqueFill = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
  theme.background.setFill()
  ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
}
searchController.searchBar.backgroundImage = opaqueFill
```

A 1×1 solid image is stretched to cover the entire search bar strip, blocking content below it.

### Caveat

This is **not always sufficient** — some configurations (notably `searchBarStyle = .default` with certain navigation controllers) still layer a translucent overlay on top of `backgroundImage`. If bleed persists after setting `backgroundImage`, try:

1. `searchController.searchBar.searchBarStyle = .minimal` then add an opaque ancestor view
2. Inspect view hierarchy in the debugger; the search bar may have `_UIBarBackground` subviews that need separate styling
3. As last resort, host the search field outside the nav bar entirely (custom toolbar)

This area of UIKit is under-documented and behaviour shifts between iOS versions; expect iteration.

## Three Appearance Slots

| Property | When active |
|----------|-------------|
| `scrollEdgeAppearance` | Content at top (large title visible, unscrolled) |
| `standardAppearance` | Content scrolled (title collapsed to inline) |
| `compactAppearance` | Compact height (landscape on non-Pro phones) |

Setting all three to the same object gives a consistent bar in all states. When they differ, the system animates between them during scroll transitions.

## Large Title Collapse — Scroll View Tracking

UINavigationController automatically finds the first UIScrollView in the visible VC's hierarchy and tracks its `contentOffset` to collapse/expand the large title. If this tracking fails, the large title stays stuck in its initial state (usually expanded) with no error or warning.

### Requirements for Tracking to Work

1. **First scroll view wins** — the scroll view must be the first (or only) scroll view added to the VC's view. If a decorative scroll view sits above the main one in the subview order, the nav bar tracks the wrong one.
2. **Top edge pinned to `view.topAnchor`** — not `safeAreaLayoutGuide.topAnchor`. The navigation controller adjusts safe-area insets itself; pinning to safe area causes double-inset and breaks offset tracking.
3. **`alwaysBounceVertical = true`** — when content is shorter than the scroll view's height, iOS won't generate scroll events. Without bounce, the large title never receives the offset change needed to collapse. Set this on any scroll-view-based screen that uses large titles.
4. **`contentInsetAdjustmentBehavior = .automatic`** (default) — don't set `.never` unless you manually handle the navigation bar inset.

### Quick Checklist

```swift
scrollView.alwaysBounceVertical = true          // ← most common miss
scrollView.topAnchor.constraint(equalTo: view.topAnchor)  // NOT safeArea
// contentInsetAdjustmentBehavior stays .automatic (default)
```

### Symptoms of Broken Tracking

| Symptom | Likely cause |
|---------|--------------|
| Large title never collapses on scroll | Missing `alwaysBounceVertical` or content too short |
| Large title collapses but never re-expands | ScrollView pinned to safeArea instead of view |
| Works on UITableView but not UIScrollView | Table/Collection views set `alwaysBounceVertical` by default; plain UIScrollView doesn't |
| Works intermittently after push/pop | Another scroll view briefly becomes first in the subview order during transitions |

## Common Pitfalls

| Pitfall | Why it's wrong |
|---------|----------------|
| Setting `backgroundColor` on iOS 26 | Large title hidden behind background layer |
| Only setting `standardAppearance` | `scrollEdgeAppearance` defaults to translucent on iOS 15+, causing a flash when scrolling to top |
| Creating new appearance objects in `viewWillAppear` without guarding | Replaces appearance mid-transition on push/pop, can cause flicker |
| Using `UINavigationBar.appearance()` globally + per-instance overrides | Global proxy wins on first layout, then per-instance takes over — ordering is unpredictable |
| UIScrollView without `alwaysBounceVertical` | Large title stuck — no scroll events when content fits in viewport |
| Setting only `UINavigationBarAppearance.backgroundColor` opaque when an embedded `UISearchBar` is present | Search bar strip stays translucent; cells bleed through it. Set `searchBar.backgroundImage` separately. |
| Setting all three slots to the same transparent appearance, then wondering why cells are visible behind the nav bar during scroll | iOS scroll views extend under the nav bar by design. Opaque (or frosted) `standardAppearance` is what hides them. |
