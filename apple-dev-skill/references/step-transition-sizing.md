# Step Transition Sizing (Wizard / Multi-Step Cards)

## Core Problem

A wizard / multi-step card swaps child VCs in and out of a single container while each step's natural content height differs (e.g. country grid 720pt → store-name form 570pt). The card should appear at the **incoming** step's final size from the start of the slide — no in-flight height shrink.

The trap: if both the outgoing and incoming child views are pinned to `containerView.top/bottom` while the container's own height is driven by low-priority preferences (`<= maxHeight`, `preferredHeight @ defaultHigh`, scrollView `content ≡ frame @ defaultLow`, …), Auto Layout solves for a **single height that minimizes the total error against all those preferences simultaneously**. Cassowary is a one-shot solver — there is no "old size first, then new size" phase. Mid-transition the container settles at a compromise height; `layoutIfNeeded()` inside the animation block animates that compromise, and the user sees the card visibly resize as the new content slides in.

This page is the standard playbook for that scenario.

## When to Apply

- A parent VC swaps child VCs in/out of a fixed-position card / panel.
- Each child VC's natural content height is different.
- Transition is animated (slide, fade, custom).
- You want the incoming card to enter at its **final** size, no mid-flight tween.

Not for: single-view height animation (use `animation.md § Animating Height in Custom Layout Views`), modal/popover sizing (use `self-sizing.md § Modal / Popover preferredContentSize`).

## The Three-Part Solution

### 1. Single source of truth: explicit container height constraint

Replace any implicit "cap-and-hug" stack (e.g. `<= maxHeight` + `preferredHeight @ low`) with one mutable height constraint that **you** drive:

```swift
final class WizardContainerViewController: UIViewController {
  private var containerHeightConstraint: NSLayoutConstraint!

  override func viewDidLoad() {
    super.viewDidLoad()
    // ...
    containerHeightConstraint = containerView.heightAnchor.constraint(
      equalToConstant: Self.cardMaxHeight
    )
    containerHeightConstraint.priority = .defaultHigh

    NSLayoutConstraint.activate([
      // required safety caps — keep these
      containerView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.cardMaxHeight),
      containerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      containerView.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
      containerHeightConstraint,
      // ...
    ])
  }
}
```

`.defaultHigh` (not `.required`) so the `<=` safe-area / keyboard guards can still compress on small screens. The required `<=` cap stops content from exceeding the max even when the measured fitting size exceeds it.

### 2. Measure the incoming child's natural height

Use `systemLayoutSizeFitting` with the card's fixed width and `verticalFittingPriority: .fittingSizeLevel` — this returns the height the child *wants* given its internal constraints:

```swift
func preferredCardHeight(for vc: UIViewController) -> CGFloat {
  vc.loadViewIfNeeded()
  let fitting = vc.view.systemLayoutSizeFitting(
    CGSize(width: Self.cardWidth, height: 0),
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
  )
  return min(max(fitting.height, minClamp), Self.cardMaxHeight)
}
```

**Prerequisite — scrollView preferred-height bridge.** If the child wraps content in a `UIScrollView`, `systemLayoutSizeFitting` will see no preferred height for the scrollView and the measurement collapses toward zero, hitting the lower clamp. Add a low-priority equality between the two layout guides inside the child so the scrollView declares its content height as its preferred frame height:

```swift
// Inside each step VC's setupUI:
let scrollHugsContent = scrollView.contentLayoutGuide.heightAnchor.constraint(
  equalTo: scrollView.frameLayoutGuide.heightAnchor
)
scrollHugsContent.priority = .defaultLow
scrollHugsContent.isActive = true
```

Read as: *"prefer to be as tall as my content; defer if the parent says otherwise."* Combined with `.fittingSizeLevel` (priority 50, lower than `.defaultLow` 250), the measurement resolves to the column's intrinsic height + scrollView chrome.

### 3. Decouple the outgoing child: snapshot + reparent

The bug returns the moment two children both pin to `container.top/bottom` with conflicting internal preferences. Solution: before committing the new height, take a snapshot of the outgoing child, lift it out of the container into the parent's view, and immediately remove the real child:

```swift
// Park new VC off-screen at the OLD container size first
centerX.constant = slideDistance * direction
containerView.layoutIfNeeded()

let snapshot = oldVC.view.snapshotView(afterScreenUpdates: true) ?? UIView()
snapshot.frame = view.convert(oldVC.view.bounds, from: oldVC.view)

oldVC.willMove(toParent: nil)
oldVC.view.removeFromSuperview()
oldVC.removeFromParent()

view.insertSubview(snapshot, aboveSubview: containerView)

// Container is now constrained solely by the new VC — commit the target
// height in a single deterministic pass while the new VC is still
// off-screen and the snapshot covers the old position.
containerHeightConstraint.constant = newPreferredHeight
view.layoutIfNeeded()

UIView.animate(withDuration: 0.3, delay: 0, options: .curveLinear) {
  centerX.constant = 0
  snapshot.transform = CGAffineTransform(translationX: -slideDistance * direction, y: 0)
  snapshot.alpha = 0
  self.containerView.layoutIfNeeded()  // animates centerX only — height is already settled
} completion: { _ in
  snapshot.removeFromSuperview()
  newVC.didMove(toParent: self)
}
```

The snapshot retains the old card's appearance and size for the entire slide-out — the user sees a clean horizontal motion with both cards at their respective final sizes, never a resize tween.

## Why Each Part Matters (Drop Any → Bug Returns)

| Drop | Symptom |
|------|---------|
| Explicit height constraint (keep implicit cap-and-hug) | Container negotiates between current and target → drifts as constraints change |
| `systemLayoutSizeFitting` measurement (hardcode per step) | Drifts silently when content / spacing / font changes |
| ScrollView `content ≡ frame @ defaultLow` bridge | `systemLayoutSizeFitting` collapses to 0 → clamp fallback → no real measurement |
| Snapshot + reparent of outgoing child | Outgoing child still pins container.top/bottom → Cassowary compromise during transition |
| `view.layoutIfNeeded()` before the animation block | New container height inside the animation block → height gets tweened |
| Snapshot parented under `containerView` instead of `view` | Snapshot moves / shrinks when the container resizes — reparent into `self.view` and convert frame: `view.convert(oldVC.view.bounds, from: oldVC.view)` |
| Snapshot left in tree after completion | Hit-testable invisible overlay blocks taps on the new card — always `snapshot.removeFromSuperview()` in animation completion |

## Decision Tree

```
Need to swap a sized child inside a fixed-position card?
├─ All children share the same size?
│  └─ Standard child-VC transition (transition(from:to:duration:options:…)).
│     No height work needed.
│
└─ Children have different natural heights?
   └─ See The Three-Part Solution above.
```

## See Also

- `self-sizing.md` — full `systemLayoutSizeFitting` reference and "Complete Vertical Constraint Chain" prerequisites.
- `animation.md § Animating Height in Custom Layout Views` — same precompute-then-animate philosophy applied to a single custom-layout view.
- `autolayout-spacing.md § Core Principle` — why Cassowary's one-shot resolution forbids the "old size first, then new size" mental model.
