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

  override func viewDidLoad() {
    super.viewDidLoad()
    // Match page background — see "Why the Host bg Must Match the Page bg" below.
    view.backgroundColor = .pageBackground  // your app's page background token

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

### Why the Host bg Must Match the Page bg

The host's default `view.backgroundColor` is `systemBackground` (white in light mode). When the inner nav bar is hidden (e.g. dashboard-style detail pages), the strip under the status bar isn't always fully painted by the inner content, and the host's white bleeds through as a band across the top of the secondary pane. Always tint the host to match the detail page's background token (a light neutral in most designs).

## Diagnostic

When you suspect overlay clipping, dump the accessibility frame of detail content and look for **width values that span the whole screen**:

```bash
axe describe-ui --udid <UDID>
```

If a card or scroll view inside the detail reports `width: 949` (or whatever ≈ full screen width) instead of `≈ secondary column width`, the detail is anchored to `view.leadingAnchor` instead of the safe-area guide. Frame data is more diagnostic than screenshots here — the screenshot only shows the visible portion, the frame dump reveals the actual extent.

## Generation Checklist

When composing or modifying an iOS 26 split view:

- [ ] Primary wrapped in `UINavigationController`; secondary set before the split first appears
- [ ] Every detail VC pins scrollable content to `safeAreaLayoutGuide.leading/trailing`
- [ ] Secondary hosting a nav controller with animated pushes → host VC wrapper in place
- [ ] Sidebar-row detail swaps go through `setViewControllerWithoutAnimation` (with post-swap `layoutIfNeeded()`)
- [ ] First diffable apply after mount is non-animated (gate on existing snapshot content)
- [ ] `viewDidLoad` order is `setupUI → load → sync → bind` for any VC with a synchronous load
- [ ] Host wrapper background matches the detail page background token
