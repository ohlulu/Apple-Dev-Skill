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
| `preferredSplitBehavior = .tile` | Optional | Honored on iOS 18 and earlier; ignored on iOS 26. Set it anyway as documentation of intent. |
| `applyColumnAffordancePolicy()` (project helper) | Yes (regular size class) | Suppresses the auto-inserted column toggle button + edge swipe on iPad full-screen; restores them on compact for accessibility. |

## Anti-Patterns

| Attempt | Why it fails |
|---------|--------------|
| Replace `UISplitViewController` with a custom `HStackView` (master + detail) | Loses system traits: column affordance, compact-size collapse, sheet presentation anchoring. Works for static layouts but breaks Stage Manager / Slide Over. |
| Drop the `UINavigationController` wrapper on primary | iOS 26 promotes the bare VC to an even more pronounced sidebar pill. The wrapper is **load-bearing**, not just cosmetic chrome. |
| Set `split.preferredSplitBehavior = .tile` and expect a flush column pair | Setting is accepted but iOS 26 still applies the overlay treatment. |
| Make the master view opaque to hide bleed-through | Doesn't address the layout issue — content still clips at the safe-area edge once the user resizes the window. |
| Bootstrap secondary from the master's `viewDidLoad` via a callback | Fires after the split commits its initial layout decision. Mount the secondary in the composer instead. |

## Push Transitions Inside Secondary Nav Slide Across Full Width

The safe-area pinning fix solves static layout. It does **not** solve push transitions inside a `UINavigationController` placed as the secondary VC.

### Symptom

- Tapping a row in the secondary detail pushes a new VC
- The new VC slides in from the right edge of the **screen** (not the right edge of the visible secondary pane)
- Mid-transition, the new VC visually "slides under the primary master" and **lands at x=0** — hidden under the master overlay
- Settled state looks fine because individual VCs are pinned to safe area, but the animation reveals the underlying full-width frame

### Root Cause

`UINavigationController`'s push animator translates the incoming/outgoing VC views by the **navigation controller's own bounds**. The secondary's nav controller has `view.bounds = full split width`, so the animator slides views across the entire screen. Safe-area pinning constrains the child VCs' content but does not change the nav controller's own frame, so the animator is unaffected.

You cannot intercept this with `preferredSplitBehavior`, `safeAreaInsets`, `additionalSafeAreaInsets`, or any UISplitView property. The fix has to be **structural** — make the nav controller's own view smaller.

### Fix — Host VC Wrapper

Wrap the navigation controller as a **child of a plain host VC** and pin the nav's view to the host's `safeAreaLayoutGuide.leadingAnchor`. The host fills the full secondary; the inner nav's frame collapses to the visible right pane. Push transitions then animate within that inner frame.

```swift
private final class SecondaryColumnHost: UIViewController {
  private let content: UIViewController  // typically a UINavigationController

  init(content: UIViewController) {
    self.content = content
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Match the page background so any uncovered strip (status-bar
    // band when the inner nav bar is hidden) reads as the page
    // surface, not systemBackground white.
    view.backgroundColor = Color.neutral50

    addChild(content)
    content.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content.view)
    NSLayoutConstraint.activate([
      content.view.topAnchor.constraint(equalTo: view.topAnchor),
      content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      // Leading pins to safe area — excludes the master overlay region.
      content.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    content.didMove(toParent: self)
  }
}

// Composer
let secondaryNav = UINavigationController(rootViewController: detailRoot)
let secondaryHost = SecondaryColumnHost(content: secondaryNav)
split.setViewController(secondaryHost, for: .secondary)
// Push as normal — transition stays inside the visible pane:
secondaryNav.pushViewController(orderDetailVC, animated: true)
```

### When You Need the Wrapper vs Just Safe-Area Pinning

| Secondary uses | Safe-area pinning alone | Host wrapper needed |
|----------------|-------------------------|---------------------|
| Single VC, swapped via `split.setViewController(_, for: .secondary)` | ✅ Sufficient | Not needed |
| `UINavigationController` with **only setViewControllers swaps** (no animated push) | ✅ Sufficient | Not needed |
| `UINavigationController` with **animated `pushViewController`** | ❌ Animation leaks across master | ✅ Required |

Note: "Sufficient" here means the master overlay clipping bug is
solved. iOS 26 also adds an **implicit slide animation** to
`setViewController(_:for:.secondary)` even without the wrapper — see
the next section to disable it.

## Detail Swap Implicit Animation on iOS 26

### Symptom

- Tapping a sidebar row swaps the secondary VC via
  `split.setViewController(detail, for: .secondary)`
- The new detail slides in from the **left edge** of the secondary
  pane every single time, even though no `animated:` parameter was
  passed (the API does not have one)
- Reads as a page transition; visually noisy when the sidebar is a
  Settings / Orders-style master where row picks should feel like
  content updates

### Root Cause

iOS 26 added an implicit transition animation to the secondary swap
path. Pre-26 this call was unanimated. The transition lives in
UIKit's containment machinery and is **not** controlled by any
public flag on `UISplitViewController` — no `animated:` overload, no
`preferredSplitBehavior` knob, no delegate hook to opt out.

### Fix

Wrap the call in `UIView.performWithoutAnimation`. This disables
both the UIKit animation block and the underlying CATransaction
implicit actions for the duration, which is enough to suppress the
slide:

```swift
UIView.performWithoutAnimation {
  split.setViewController(detail, for: .secondary)
}
```

For a project with multiple sidebar-driven detail panes, hoist a
thin extension to keep call sites clean and the workaround
documented in one place:

```swift
public extension UISplitViewController {
  func setViewControllerWithoutAnimation(
    _ viewController: UIViewController,
    for column: UISplitViewController.Column
  ) {
    UIView.performWithoutAnimation {
      setViewController(viewController, for: column)
    }
  }
}
```

### When to Disable vs Keep

| Sidebar UX intent | Animation | Use the wrapper? |
|-------------------|-----------|------------------|
| Sidebar row ≈ "change which content the pane is showing" (Settings, Orders) | Off | ✅ |
| Sidebar row ≈ "navigate to a different screen" (Mail accounts switching) | On | Skip the wrapper |

The canonical Settings / iPad master-detail metaphor is the former.
The slide reads as a page transition the user didn't ask for.

### What Doesn't Work

- `split.setViewController(detail, for: .secondary, animated: false)` — no such overload
- `preferredSplitBehavior = .tile` — ignored on iOS 26 in this respect
- Calling on a background runloop or `DispatchQueue.main.async` — the
  animation is scheduled inside the same runloop turn as the swap
- Setting `UIView.setAnimationsEnabled(false)` globally — works but is
  too blunt; can swallow legitimate animations from other call paths

### Strengthen the Wrapper for Sub-Layer Animations

`UIView.performWithoutAnimation` alone does not always suppress
implicit CALayer animations triggered during the swap's layout pass
— things like `CAGradientLayer.colors` crossfades,
`UISegmentedControl` selector-pill movement, `UISwitch` thumb
animation on initial `isOn`. Strengthen the wrapper:

```swift
public extension UISplitViewController {
  func setViewControllerWithoutAnimation(
    _ vc: UIViewController,
    for column: UISplitViewController.Column
  ) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    UIView.performWithoutAnimation {
      setViewController(vc, for: column)
      view.layoutIfNeeded()           // force layout in disabled scope
    }
    CATransaction.commit()
    scrubAnimations(in: vc.view)      // sweep any queued animations
  }

  private func scrubAnimations(in view: UIView) {
    view.layer.removeAllAnimations()
    for sub in view.subviews { scrubAnimations(in: sub) }
  }
}
```

The four parts — transaction-disable + UIView block + layoutIfNeeded
+ post-commit sweep — each catch a different class of animation:

| Layer | Catches |
|-------|---------|
| `CATransaction.setDisableActions(true)` | Sub-layer implicit actions (gradient colors, segmented pill, switch thumb, layer position/bounds) |
| `UIView.performWithoutAnimation` | UIKit animation blocks inside the new VC's `viewDidLoad` / `viewWillAppear` |
| `view.layoutIfNeeded()` inside the scope | Layout-driven animations triggered by the first pass (intrinsic-size changes propagating up) |
| `removeAllAnimations` sweep after commit | Animations the system already queued on layers before commit closed |

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

### Async State Loads Bypass the Wrapper

A stronger version of the same trap. The wrapper's
`CATransaction.setDisableActions` scope **closes when
`setViewController` returns** — typically within one runloop turn.
But Settings detail VCs commonly load state asynchronously:

```swift
override func viewDidLoad() {
  super.viewDidLoad()
  setupUI()
  bindViewModel()
  Task { await viewModel.loadStatus() }   // <— this runs AFTER the wrapper
                                          //    closes its transaction
}

func applyState() {
  statusCard.configure(with: viewModel.status)   // gradient color
                                                 // crossfade happens HERE,
                                                 // outside the wrapper's scope
}
```

Symptom: VC header appears instantly, table content is instant
(if the diffable fix is applied), but a *specific element* later
fades / crossfades / settles in — typical culprits being a gradient
banner whose colors change when status arrives, or a form whose
segment / switch settles into the loaded value.

Fix: wrap the state-update method itself in
`CATransaction.setDisableActions(true)`. The wrapper covers the
swap moment; this covers the post-swap async settle.

```swift
func applyState() {
  CATransaction.begin()
  CATransaction.setDisableActions(true)
  defer { CATransaction.commit() }
  statusCard.configure(with: viewModel.status)
  pricingCard.configure(with: viewModel.status, isLoading: viewModel.isLoading)
}
```

If the screen also has *intentional* state transitions that should
animate (e.g. trial → active after a successful purchase), gate the
disable on "is this the first apply" with a one-shot flag. The
initial mount paint is unambiguously a content load, not a
transition; subsequent applies can opt in to animation.

### Why the Host bg Must Match the Page bg

The host's default `view.backgroundColor` is `systemBackground` (white in light mode). When the inner nav bar is hidden (e.g. dashboard-style detail pages), the strip under the status bar isn't always fully painted by the inner content, and the host's white bleeds through as a band across the top of the secondary pane. Always tint the host to match the detail page's bg token (typically `neutral-50`).

## Diagnostic

When you suspect overlay clipping, dump the accessibility frame of detail content and look for **width values that span the whole screen**:

```bash
axe describe-ui --udid <UDID>
```

If a card or scroll view inside the detail reports `width: 949` (or whatever ≈ full screen width) instead of `≈ secondary column width`, the detail is anchored to `view.leadingAnchor` instead of the safe-area guide. Frame data is more diagnostic than screenshots here — the screenshot only shows the visible portion, the frame dump reveals the actual extent.

## Reference Implementations

- **Static safe-area pinning**: `CustomerDetailViewController` / `OrderDetailViewController` `setupScroll()` — pin the scroll view to `safeAreaLayoutGuide` for leading/trailing. Copy this for any new detail VC.
- **Push-transition host wrapper**: `CustomerComposer.SecondaryColumnHost` — wrap the secondary nav whenever the detail flow uses animated `pushViewController` inside the secondary column.
