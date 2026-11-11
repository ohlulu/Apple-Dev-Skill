# UISplitViewController on iOS 26

## iOS 26 Behavior Change — Primary Column Is an Overlay

On iOS 26, `UISplitViewController(style: .doubleColumn)` renders the primary column as a **floating glass card overlaid above the secondary column**, not beside it. The secondary column's view bounds span the **entire screen width**, with the master visually layered on top.

This is the Liquid Glass sidebar treatment. It is the default — there is no opt-out via `preferredSplitBehavior = .tile` (the setting is accepted but does not flatten the overlay).

### Symptom

- Detail content draws under the floating master and gets clipped on the leading edge
- Card titles, form fields, and section headers appear to start *inside* the master card
- Only obvious when the detail has wide content; an empty placeholder secondary looks fine (which masks the bug during initial development)

### Root Cause

Detail view controllers anchored to `view.leadingAnchor` / `view.trailingAnchor` extend from x=0 to the full screen width. iOS does not clip the secondary VC's view to the space beside the master — it expects the VC to use the safe-area guide, into which iOS folds the floating master's frame.

### Fix

Anchor scrollable detail content to `view.safeAreaLayoutGuide.leadingAnchor` / `trailingAnchor`:

```swift
NSLayoutConstraint.activate([
  scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
  scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
  scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
  scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
])
```

iOS automatically inset `safeAreaLayoutGuide` past the master overlay. No manual offset, no observation of split-view state, no size-class branching needed.

## Composer Configuration Checklist

| Step | Required? | Why |
|------|-----------|-----|
| Wrap primary in `UINavigationController` with `prefersLargeTitles = true` | Yes | A bare VC as primary triggers an even more aggressive sidebar pill style. The nav controller anchors the column visually. |
| Call `split.setViewController(_, for: .primary)` before `.secondary` | Yes | Standard ordering. |
| Set an initial secondary VC (real or placeholder) **before returning the split** | Yes | If secondary is `nil` when the split first appears, iOS commits to a single-column sidebar layout for that lifetime. Setting secondary lazily from `viewDidLoad` is too late. |
| `preferredSplitBehavior = .tile` | Optional | Ignored on iOS 26 (see intro). Set it anyway as documentation of intent. |
| Column affordance policy (if the design hides the toggle) | Optional (regular size class) | If the design calls for it, suppress the auto-inserted column toggle button + edge swipe on iPad full-screen via `presentsWithGesture` / hiding the leading bar button; restore them on compact for accessibility. |

## Anti-Patterns

| Attempt | Why it fails |
|---------|--------------|
| Replace `UISplitViewController` with a custom `HStackView` (master + detail) | Loses system traits: column affordance, compact-size collapse, sheet presentation anchoring. Works for static layouts but breaks Stage Manager / Slide Over. |
| Drop the `UINavigationController` wrapper on primary | iOS 26 promotes the bare VC to an even more pronounced sidebar pill. The wrapper is **load-bearing**, not just cosmetic chrome. |
| Set `split.preferredSplitBehavior = .tile` and expect a flush column pair | Ignored on iOS 26 (see intro). |
| Make the master view opaque to hide bleed-through | Doesn't address the layout issue — content still clips at the safe-area edge once the user resizes the window. |
| Bootstrap secondary from the master's `viewDidLoad` via a callback | Fires after the split commits its initial layout decision. Mount the secondary in the composer instead. |

## Every Column Root Is a Navigation Controller You Built

Hand `setViewController(_:for:)` a `UINavigationController` for every column, never a plain view controller and never a plain host that wraps a nav. A column-style split wraps any other root in a navigation controller of its own — `UISplitViewController.h`: "If the vc is not a UINavigationController, one will be created, except for UISplitViewControllerColumnCompact." That implicit nav costs two things:

- Its bar is empty and transparent, yet it consumes 54pt of safe area, so the whole pane sits 54pt low and no per-page top padding removes the cause.
- It does not exist yet when `setViewController(_:for:)` returns, so `viewController(for:)?.navigationController` is `nil` and chrome set through it (`prefersLargeTitles`, bar appearance) never applies — the title stays inline for good.

Build the nav, configure its chrome, then install it. For a pane with a drill-down, keep one persistent nav and replace its stack with `setViewControllers`; for sidebar rows that are peers, install a new nav per detail.

### Push Transitions Inside the Secondary Nav

The secondary nav's view spans the full split width like any secondary column (see the intro), and an animated `pushViewController` translates both views across that full width. With detail content pinned to the safe area this stays cosmetic:

- Content never enters the master's region. The incoming view carries its final safe-area inset through the whole push, so its content travels from the screen's trailing edge to the visible pane; the outgoing content slides under the master card, which hides it.
- The push's dimming and the incoming view's background edge sweep across the strips the master card does not cover — above the card and the gutter beside it.

Content pinned to `view.leadingAnchor` does slide visibly under the master and land hidden beneath it; that is the overlay bug above, and safe-area pinning is its fix. Do not shrink the nav's frame with a host view controller to keep the push inside the pane: the host is a non-nav column root and brings the implicit nav back.

## Detail Swap "Settling" Animation on iOS 26

### Symptom

- Tapping a sidebar row swaps the secondary VC via
  `split.setViewController(detail, for: .secondary)`
- The new VC's content appears to "settle" in over ~1 frame:
  gradient banner color crossfades, segmented control pill slides
  into position, labels grow into place, switches animate their
  thumb
- Reads as a page transition; visually noisy when the sidebar is a
  Settings / Orders-style master where row picks should feel like
  content updates
- Easy to misread as "the swap animates". The swap itself is
  instant. What's animating is the **first layout pass of the new
  VC's view tree**.

### Root Cause (verified)

Starting on iOS 26, the container's add-child sequence does **not**
propagate the final size + safe-area insets to the incoming VC's
view BEFORE the appearance transition begins. The view is added
with a `.zero` frame (and `.zero` safe-area insets); Auto Layout
then resolves the real values inside the transition window, and
every subview's frame appears to grow / settle from the origin.

Sub-elements that look like they're individually animating are NOT
separate animations — they are **intermediate frames of that one
Auto Layout resolve**. The gradient banner isn't crossfading; its
layer bounds are growing from `.zero`. The segmented pill isn't
moving; the control's bounds are growing from `.zero` and the pill
is positioning relative to the new bounds. Same mechanism, many
visible faces.

Apple shipped a partial fix in **iOS 26.2 for the
`pushViewController` path**
(https://darjeelingsteve.com/articles/Fixing-UINavigationController-Push-Animation-Layout-Issues-on-iOS-26.html).
The **`setViewController(_:for:)` path is still affected as of
26.4** — same underlying mechanism, different entry point
(verified empirically on simulator).

### Fix

Force the new VC's view to lay out **AFTER `setViewController`
returns** so Auto Layout resolves against real bounds + safe area
before the transition window opens:

```swift
public extension UISplitViewController {
  func setViewControllerWithoutAnimation(
    _ viewController: UIViewController,
    for column: UISplitViewController.Column
  ) {
    UIView.performWithoutAnimation {
      setViewController(viewController, for: column)
      // CRITICAL: lay out AFTER the swap so the new VC's view picks up
      // real bounds + safe area from its parent. Calling this BEFORE
      // setViewController lays out against .zero and achieves nothing.
      viewController.view.layoutIfNeeded()
    }
  }
}
```

`UIView.performWithoutAnimation` is belt + braces against any
animation block UIKit may schedule around the column transition
itself; it is NOT what kills the settling animation. The
`layoutIfNeeded` after the swap is the load-bearing line.

### When to Disable vs Keep

| Sidebar UX intent | Animation | Use the wrapper? |
|-------------------|-----------|------------------|
| Sidebar row ≈ "change which content the pane is showing" (Settings, Orders) | Off | ✅ |
| Sidebar row ≈ "navigate to a different screen" (Mail accounts switching) | On | Skip the wrapper |

The canonical Settings / iPad master-detail metaphor is the former.
The "settling" animation reads as a page transition the user didn't
ask for.

### What Doesn't Work (and why)

- `split.setViewController(detail, for: .secondary, animated: false)` — no such overload
- `preferredSplitBehavior = .tile` — ignored on iOS 26 (see intro)
- `DispatchQueue.main.async { setViewController(...) }` — the layout
  is still deferred relative to the next layout pass
- `UIView.setAnimationsEnabled(false)` globally — the animation is
  not in a UIView block; it's Auto Layout resolving over real time

### Pitfall: Symptom-Suppression Doesn't Cure the Cause

Do not stack suppression layers (`CATransaction.setDisableActions`,
`removeAllAnimations` sweeps, per-VC `disableActions` wraps) as each
new sub-animation appears — each layer hides one symptom while the
underlying zero-frame Auto Layout pass keeps running and surfaces
through the next sub-layer. The real cause is one layout pass against
a `.zero` frame; one `viewController.view.layoutIfNeeded()` after the
swap replaces every suppression layer. If you're about to add
suppression layer N+1, layer N was probably already a workaround —
stop and apply the layout fix instead.

### Don't Stop at the VC Swap — Audit the Detail's Initial Apply Too

After wrapping the swap, the slide may still appear because the
**detail VC's own content** is animating in. Common offenders inside
a fresh-mounted detail pane:

- `UITableViewDiffableDataSource.apply(_, animatingDifferences:)` /
  `UICollectionViewDiffableDataSource.apply(...)` — the first apply
  hits an empty data source, so every row counts as an insertion and
  iOS 26 animates each one in (reads as a row-by-row slide-in)
- `UIView.transition(with: ..., options: .transitionCrossDissolve)` —
  cross-fade reloads triggered from `viewWillAppear` / a `Combine`
  publisher that fires on initial bind
- `UIView.animate { ... }` blocks that wrap `layoutIfNeeded` after
  loading remote data

Rule of thumb for **sidebar-mounted detail VCs**: the *first*
apply / reload after the VC mounts should be non-animated; only
user-initiated diffs (add / edit / delete) should animate. The data
source itself is the source of truth for "has the user seen content
before":

```swift
func applySnapshot() {
  var snap = NSDiffableDataSourceSnapshot<Section, Item>()
  // ... build snapshot ...
  // Only animate when the user can actually perceive a diff.
  let hadContent = dataSource.snapshot().numberOfItems > 0
  dataSource.apply(snap, animatingDifferences: hadContent)
}
```

This pattern composes cleanly with the swap-wrapper fix: the swap is
instant, the first apply paints rows immediately, and subsequent
applies still animate so an add/delete remains legible.

The usual smell when you've only solved half the problem: the *VC
header* appears instantly (proves the swap is non-animated), but the
rows below it slide / fade in a frame later (proves the detail VC's
own apply still animates).

### Async State Loads After Mount

A related but **distinct** concern. The swap wrapper covers the
mount moment. ViewModels that load state asynchronously fire their
`onChange` AFTER `viewDidLoad` returns:

```swift
override func viewDidLoad() {
  super.viewDidLoad()
  Task { await viewModel.loadStatus() }   // <— fires AFTER mount
}
```

With the **real fix in place** (layout forced on first add), the
async state arrival into already-laid-out subviews is genuinely
clean: setting `label.text` or `gradientLayer.colors` no longer
rides an Auto Layout resolve, so it lands instantly. No further
suppression needed.

### Sync State Loads During Mount (Bind-Before-Load Trap)

The more dangerous sibling, and the one that masquerades as the
iOS 26 `.zero`-frame regression: a *synchronous* `viewModel.load()`
that fires `onChange` inside `viewDidLoad`, whose bind callback runs
`UIView.animate` while the view frame is still `.zero`. Symptom is
identical by eye (expand-from-origin on mount) but the iOS 26 swap
fix doesn't help, and a sibling detail VC on the same swap path that
binds *after* loading won't animate.

**Canonical treatment** — full mechanism, empty-body diagnostic, and
the `load → sync → bind` reorder fix: `implicit-animations.md` →
"Bind-Before-Load: The Sync-Fire Trap".

This is independent of — and orthogonal to — the iOS 26 swap-layout
fix above. Both can exist in the same codebase; both must be fixed
separately. Don't conflate the two when diagnosing.

If you see a state-update animation after the layout fix is in
place, the culprit is usually a UIKit control with its own
*pre-existing* implicit animation (these have been around since
iOS 13+, not iOS 26 new):

- `UISegmentedControl.selectedSegmentIndex` animates the pill move
  for **delta** changes (0 → 1 animates; 0 → 0 doesn't)
- `UISwitch.setOn(_, animated:)` defaults `animated: true` — use
  `setOn(_, animated: false)` on initial sync
- `CAGradientLayer.colors` change is a free animation — wrap the
  property write in `CATransaction.setDisableActions(true)` only
  for the SPECIFIC layer property, not the whole VC

These are legit per-control concerns. Address them at the
control-level if and when they matter, not by blanket-disabling
actions on the whole view tree.

## Diagnostic

When you suspect overlay clipping, dump the accessibility frame of detail content and look for **width values that span the whole screen**:

```bash
axe describe-ui --udid <UDID>   # full tree; sim-use's outline omits the scroll views and cards measured here
```

If a card or scroll view inside the detail reports `width: 949` (or whatever ≈ full screen width) instead of `≈ secondary column width`, the detail is anchored to `view.leadingAnchor` instead of the safe-area guide. Frame data is more diagnostic than screenshots here — the screenshot only shows the visible portion, the frame dump reveals the actual extent.

## Generation Checklist

When composing or modifying an iOS 26 split view:

- [ ] Primary wrapped in `UINavigationController`; secondary set before the split first appears
- [ ] Every detail VC pins scrollable content to `safeAreaLayoutGuide.leading/trailing`
- [ ] Every column root is a `UINavigationController` built and configured before `setViewController(_:for:)` — no plain VC, no host VC around a nav
- [ ] Sidebar-row detail swaps go through `setViewControllerWithoutAnimation` (with post-swap `layoutIfNeeded()`)
- [ ] First diffable apply after mount is non-animated (gate on existing snapshot content)
- [ ] `viewDidLoad` order is `setupUI → load → sync → bind` for any VC with a synchronous load
