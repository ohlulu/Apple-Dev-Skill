# Animation Patterns

## Core Principle

Keep animations minimal and snappy. Most UI state changes need only a short linear fade. Avoid spring animations unless explicitly requested.

## Default: Linear Fade 0.1s

The standard animation for showing, hiding, or toggling UI elements is a **0.1s linear alpha change**. This covers the majority of cases.

```swift
UIView.animate(withDuration: 0.1, delay: 0, options: .curveLinear) {
    self.overlayView.alpha = 1
}
```

Use this for:
- Showing / hiding views
- Toggling element visibility
- Fading in loading indicators, toasts, or overlays

## Transitions: Duration Varies by Case

Transitions — view controller push/present/dismiss, layout constraint animations, or any multi-element choreography — are **not bound to 0.1s**. Choose duration based on the specific case and the amount of visual change involved.

```swift
// Layout constraint animation — duration depends on distance/complexity
self.topConstraint.constant = newValue
UIView.animate(withDuration: 0.25, delay: 0, options: .curveLinear) {
    self.view.layoutIfNeeded()
}
```

## Curve: Always Linear

Use `.curveLinear` by default. Do not use spring animations (`UIView.animate(withSpringDuration:)`, `usingSpringWithDamping`) unless the user explicitly requests spring behavior.

```swift
// ✅ Default
UIView.animate(withDuration: 0.1, delay: 0, options: .curveLinear) { ... }

// ❌ Don't add spring unless requested
UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, ...) { ... }
```

## Expand / Collapse Choreography

For content that expands to reveal more items (unit values, details, accordion sections). Two-phase structure makes the motion feel intentional, not mechanical.

### Expand: Spring Height + Staggered Reveal

Two animations fire simultaneously:

1. **Height** — spring grows the container.
2. **Content** — each item staggers in with fade + scale.

```swift
func animateExpand(row: ExpandableRow) {
    // Prep: unhide items, start invisible + scaled down
    row.prepareExpandAnimation()

    // 1. Spring height
    UIView.animate(
        withDuration: 0.4,
        delay: 0,
        usingSpringWithDamping: 0.85,
        initialSpringVelocity: 0,
        options: .curveEaseOut
    ) {
        self.layoutIfNeeded()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    // 2. Staggered values reveal
    row.animateValuesIn()
}
```

Prepare phase — set state before animation starts:
```swift
func prepareExpandAnimation() {
    for view in collapsibleViews {
        view.isHidden = false
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
    }
    flowView.setNeedsLayout()
}
```

Stagger phase — each item fades in with slight delay:
```swift
func animateValuesIn() {
    let staggerDelay: TimeInterval = 0.04
    for (i, view) in collapsibleViews.enumerated() {
        UIView.animate(
            withDuration: 0.3,
            delay: staggerDelay * Double(i),
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            view.alpha = 1
            view.transform = .identity
        }
    }
}
```

### Collapse: Fade Out → Then Shrink

Two-phase sequential — content disappears first, then container closes:

```swift
func animateCollapse(row: ExpandableRow) {
    // Phase 1: fast fade out + scale down
    UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
        row.setCollapsedVisuals()  // alpha = 0, scale = 0.85
    } completion: { _ in
        // Phase 2: spring height shrink
        row.applyCollapsedLayout()  // isHidden = true → triggers re-layout
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.layoutIfNeeded()
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
    }
}
```

### Why This Structure Works

| Aspect | Expand | Collapse |
|--------|--------|----------|
| Phases | Simultaneous (height + stagger) | Sequential (fade → height) |
| Height | Spring 0.4s, damping 0.85 | Spring 0.3s, damping 0.9 |
| Content | Stagger 0.04s gap, scale 0.85→1.0 | All simultaneous, 0.15s |
| Feel | "Items unfold one by one" | "Tuck away, then close" |

Expand is slower and playful (discovery). Collapse is faster and direct (dismissal). Asymmetric timing mirrors iOS system patterns.

### Prerequisites

- Use `isHidden` to toggle subview visibility, not add/remove. Container views like `UIStackView` and `FlowLayoutView` should skip hidden subviews in layout (`where !subview.isHidden`).
- Store references to collapsible views in an array at configure time.
- Never call `removeAllItems()` + re-add inside a toggle — that destroys views and can't be animated.
- Use `setNeedsLayout()` after changing `isHidden` so the container recalculates.

## Animating Height in Custom Layout Views

`UIStackView` handles `isHidden` animation on arranged subviews automatically — the stack animates the height transition when `isHidden` is set inside a `UIView.animate` block.

Custom layout views (e.g. a flow/tag-cloud layout that positions subviews in `layoutSubviews`) do **not** get this for free. Four pitfalls arise:

> For the related but distinct scenario of **swapping child VCs of different heights inside a fixed-position card** (wizard / multi-step transitions), see [step-transition-sizing.md](step-transition-sizing.md). Same precompute-then-animate philosophy; different decoupling problem (two pinned children competing for container height).

### Pitfall 1: `isHidden` Is Not Animatable

`isHidden` takes effect immediately, even inside an animation block. For UIStackView, Apple intercepts this and converts it to a height animation. Custom views get no such magic — the layout change happens instantly.

```swift
// ✅ UIStackView — height animates
UIView.animate(withDuration: 0.3) {
    self.childStack.isHidden = false  // stack animates height
    self.scrollView.layoutIfNeeded()
}

// ❌ Custom layout — height jumps
UIView.animate(withDuration: 0.3) {
    self.altView.isHidden = false     // layout recalcs instantly
    self.scrollView.layoutIfNeeded()
}
```

### Pitfall 2: `invalidateIntrinsicContentSize()` Causes Deferred Layout

Custom layout views often call `invalidateIntrinsicContentSize()` inside `layoutSubviews` when the computed height changes. This schedules a **second** Auto Layout pass that runs **after** the animation block, causing the parent container to jump in height.

```swift
// Inside custom layout view:
override func layoutSubviews() {
    super.layoutSubviews()
    let newHeight = computeHeight()
    // ❌ This triggers a deferred pass outside the animation block
    if abs(bounds.height - newHeight) > 1 {
        invalidateIntrinsicContentSize()
    }
}
```

### Solution: Precompute + Separate Concerns

Split the two concerns:
1. **Before** animation: compute the target height and notify Auto Layout.
2. **Inside** animation: `layoutIfNeeded()` — Auto Layout uses the pre-computed size to resize the container (animated), then `layoutSubviews()` repositions child views (also animated).

```swift
// Add to custom layout view:
private var cachedHeight: CGFloat?

func precomputeIntrinsicHeight() {
    guard bounds.width > 0 else { return }
    let newHeight = computeHeight(for: bounds.width)
    guard cachedHeight != newHeight else { return }
    cachedHeight = newHeight
    invalidateIntrinsicContentSize()
}

override var intrinsicContentSize: CGSize {
    if let cached = cachedHeight {
        return CGSize(width: UIView.noIntrinsicMetric, height: cached)
    }
    return CGSize(width: UIView.noIntrinsicMetric,
                  height: computeHeight(for: bounds.width))
}
```

Animation call site:

```swift
// 1. Change visibility
for view in altViews { view.isHidden = false; view.alpha = 0 }

// 2. Pre-compute target height (notifies Auto Layout)
flowView.precomputeIntrinsicHeight()
flowView.setNeedsLayout()  // ensure repositioning runs

// 3. Animate — one block handles both card height + subview repositioning
UIView.animate(withDuration: 0.4, delay: 0,
               usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
               options: .curveEaseOut) {
    self.findScrollAncestor()?.layoutIfNeeded()
}
```

Why `arrangeItems()` won't re-invalidate: when `layoutIfNeeded()` runs, Auto Layout first updates the view's bounds to match the cached intrinsic size, **then** triggers `layoutSubviews()`. By the time `arrangeItems()` checks `bounds.height` vs computed height, they match — no re-invalidation.

### Pitfall 3: `layoutIfNeeded()` Target Scope

Calling `superview?.superview?.layoutIfNeeded()` is fragile — the view hierarchy depth can change. Always walk up to the nearest `UIScrollView`:

```swift
private func findScrollAncestor() -> UIScrollView? {
    var current: UIView? = superview
    while let view = current {
        if let scroll = view as? UIScrollView { return scroll }
        current = view.superview
    }
    return nil
}
```

The scroll view is the natural animation boundary — it contains the full layout tree that needs to update (cards, stacks, rows).

### Pitfall 4: `setNeedsLayout()` Required Even When Height Unchanged

When expand/collapse doesn't change the number of lines (e.g. all content fits on one line), `precomputeIntrinsicHeight()` sees no height change and skips `invalidateIntrinsicContentSize()`. Without `setNeedsLayout()`, `arrangeItems()` never runs and subviews stay at their old positions.

```swift
// ❌ Primary value stuck at expanded position after single-line collapse
flowView.precomputeIntrinsicHeight()  // same height → skips invalidate
// No layout pass → arrangeItems never runs

// ✅ Always mark for layout
flowView.precomputeIntrinsicHeight()
flowView.setNeedsLayout()  // arrangeItems will reposition subviews
```

### Decision Tree

```
Animating height change in a container?
├─ UIStackView arranged subview?
│  └─ Set isHidden inside animation block → auto-animated ✓
│
└─ Custom layout view (FlowLayout, manual frames)?
   ├─ 1. Change isHidden outside animation block
   ├─ 2. Call precomputeIntrinsicHeight() → caches target size
   ├─ 3. Call setNeedsLayout() → ensures repositioning
   └─ 4. Animation block: scrollAncestor.layoutIfNeeded()
```

---

## Text Expand / Collapse (UILabel Height Animation)

Animating a UILabel between a truncated state (e.g. 3 lines) and full content requires a different strategy from the subview-based expand/collapse above. `numberOfLines` changes cause **instant text reflow** — the content snaps to its new state before the frame animation starts, producing a visual disconnect.

### The Problem with `numberOfLines`

```swift
// ❌ Not smooth — text reflows immediately, frame animates separately
label.numberOfLines = 0  // text snaps to full content
UIView.animate(withDuration: 0.35, ...) {
    self.layoutIfNeeded()  // frame grows, but text already changed
}
```

| Phase | What happens |
|-------|-------------|
| Frame 0 | `numberOfLines = 0` — label renders ALL text instantly |
| Frame 0 | Old frame still at 3-line height — extra text overflows or is clipped |
| Frame 1…N | Frame animates to new height — but text was already there |

Expand looks like a "sliding reveal" (acceptable). Collapse looks broken — text snaps to 3 lines while the frame is still tall, leaving empty space that then shrinks.

### Solution: Constraint-Driven Height with Clip Container

Keep `numberOfLines = 0` at all times. Control visible height with a constraint on a clipping container. The text never reflows — only the visible area changes.

```
┌─ NoteRowView ─────────────────────────┐
│  [bullet]  ┌─ labelContainer ───────┐ │
│            │  clipsToBounds = true   │ │
│            │  ┌─ contentLabel ────┐  │ │
│            │  │ numberOfLines = 0 │  │ │
│            │  │ (full text)       │  │ │
│            │  └───────────────────┘  │ │
│            │  ← height constraint → │ │
│            └────────────────────────┘ │
└───────────────────────────────────────┘
```

Setup:

```swift
// Label always renders full text
contentLabel.numberOfLines = 0
contentLabel.lineBreakMode = .byTruncatingTail

// Container clips overflow during animation
labelContainer.clipsToBounds = true

// Label pinned to container, bottom at lowered priority
contentLabel.topAnchor.constraint(equalTo: labelContainer.topAnchor),
contentLabel.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor),
contentLabel.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor),
{
    let c = contentLabel.bottomAnchor.constraint(equalTo: labelContainer.bottomAnchor)
    c.priority = .defaultHigh  // yields to height constraint when active
    return c
}()
```

Height constraint:

```swift
private var collapsedHeightConstraint: NSLayoutConstraint?

private var collapsedTextHeight: CGFloat {
    let font = contentLabel.font ?? .systemFont(ofSize: 15)
    return ceil(font.lineHeight * 3)  // 3 lines
}

private func ensureCollapsedConstraint() {
    let maxHeight = collapsedTextHeight
    if let existing = collapsedHeightConstraint {
        existing.constant = maxHeight
    } else {
        let c = labelContainer.heightAnchor.constraint(
            lessThanOrEqualToConstant: maxHeight
        )
        c.priority = .required
        collapsedHeightConstraint = c
    }
}
```

### Expand: Deactivate Constraint → Spring Height

```swift
func applyExpanded() {
    collapsedHeightConstraint?.isActive = false
}

// In parent cell:
row.applyExpanded()
UIView.animate(
    withDuration: 0.4,
    delay: 0,
    usingSpringWithDamping: 0.85,
    initialSpringVelocity: 0,
    options: .curveEaseOut
) {
    self.layoutIfNeeded()
    collectionView.collectionViewLayout.invalidateLayout()
    collectionView.layoutIfNeeded()
}
```

Result: frame grows smoothly, text is revealed line by line as the container expands. Feels like a sliding reveal.

### Collapse: Activate Constraint → Spring Height

```swift
func applyCollapsed() {
    ensureCollapsedConstraint()
    collapsedHeightConstraint?.isActive = true
}

// In parent cell:
row.applyCollapsed()
UIView.animate(
    withDuration: 0.3,
    delay: 0,
    usingSpringWithDamping: 0.9,
    initialSpringVelocity: 0,
    options: .curveEaseOut
) {
    self.layoutIfNeeded()
    collectionView.collectionViewLayout.invalidateLayout()
    collectionView.layoutIfNeeded()
}
```

Result: frame shrinks smoothly, text is masked from bottom upward. No text reflow snap.

### Why This Works

| Aspect | `numberOfLines` toggle | Constraint + clip |
|--------|----------------------|-------------------|
| Text reflow | Instant snap — not animatable | Never happens — text always rendered |
| Frame change | Animatable via `layoutIfNeeded` | Same |
| Expand visual | Sliding reveal (ok) | Sliding reveal (same) |
| Collapse visual | Text snaps → empty space → shrink (bad) | Smooth mask from bottom (good) |
| Truncation "..." | Automatic from `numberOfLines` | Not shown (chevron indicates overflow instead) |

### Overflow Detection for Text

Use the same two-pass pattern from [overflow-detection](overflow-detection.md), adapted for text height:

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    guard pendingOverflowCheck, labelContainer.bounds.width > 0 else { return }
    pendingOverflowCheck = false

    let fullHeight = textHeight(for: contentLabel)
    let maxCollapsed = collapsedTextHeight
    if fullHeight > maxCollapsed + 1 {
        DispatchQueue.main.async { [weak self] in
            self?.onOverflowDetected?()
        }
    }
}

private func textHeight(for label: UILabel) -> CGFloat {
    guard let text = label.text, let font = label.font else { return 0 }
    let width = label.bounds.width > 0 ? label.bounds.width : labelContainer.bounds.width
    guard width > 0 else { return 0 }
    return (text as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: .usesLineFragmentOrigin,
        attributes: [.font: font],
        context: nil
    ).height
}
```

### Anti-Patterns

#### ❌ `performBatchUpdates(nil)` for Height Animation

```swift
// ❌ Causes visual glitches — the collection view recalculates cell
// sizes in its own animation context which conflicts with the
// constraint-driven height change
row.animateExpand()
collectionView.performBatchUpdates(nil)
```

Use `invalidateLayout()` + `layoutIfNeeded()` inside `UIView.animate` instead. This keeps the constraint change and the collection view layout in the same animation transaction.

#### ❌ Toggling `numberOfLines` for Animated Height Changes

```swift
// ❌ Text reflows instantly — frame and content are out of sync
label.numberOfLines = isExpanded ? 0 : 3
UIView.animate { self.layoutIfNeeded() }
```

Use a height constraint on a clipping container instead (see above).

## Staggered Entrance Animation (Collection View Cells)

Cards fly in one by one when a screen first appears — each cell slides from off-screen with a per-item stagger delay, then reveals inner content in a cascade.

### Architecture: `willDisplay` + `Task.sleep`

Use `collectionView(_:willDisplay:forItemAt:)` to trigger per-cell entrance. This is the most robust hook — it fires exactly when each cell is about to appear, requires no `layoutIfNeeded()` hack, and doesn't depend on `visibleCells` (which is empty before layout).

```swift
// ViewController
private var entranceAnimatedItems: Set<Int> = []
private var isEntranceComplete = false
private var entranceBaseDelay: TimeInterval = 0.35

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // Capture actual push transition duration
    if let d = transitionCoordinator?.transitionDuration, d > 0 {
        entranceBaseDelay = d
    }
}

override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    isEntranceComplete = true  // Stop future entrance animations
}

func collectionView(
    _ collectionView: UICollectionView,
    willDisplay cell: UICollectionViewCell,
    forItemAt indexPath: IndexPath
) {
    guard !isEntranceComplete,
          let cell = cell as? MyCell,
          !entranceAnimatedItems.contains(indexPath.item) else { return }

    entranceAnimatedItems.insert(indexPath.item)
    cell.prepareForEntrance()
    cell.animateEntrance(
        delay: entranceBaseDelay + Double(indexPath.item) * 0.1
    )
}
```

### Cell Implementation

```swift
// Cell
func prepareForEntrance() {
    card.transform = CGAffineTransform(
        translationX: -UIScreen.main.bounds.width, y: 0
    )
    card.alpha = 0.3
    // Hide inner content — will fade in after card lands
    [swatch1, swatch2, swatch3].forEach { $0.alpha = 0 }
    nameLabel.alpha = 0
}

func animateEntrance(delay: TimeInterval) {
    Task { @MainActor [weak self] in
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        guard let self else { return }

        // Phase 1: card slides in
        UIView.animate(
            withDuration: 0.4, delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.3,
            options: .curveEaseOut
        ) {
            self.card.transform = .identity
            self.card.alpha = 1
        } completion: { _ in
            // Phase 2: inner content cascades in
            let swatches = [self.swatch1, self.swatch2, self.swatch3]
            for (i, v) in swatches.enumerated() {
                UIView.animate(
                    withDuration: 0.18,
                    delay: Double(i) * 0.07,
                    options: .curveEaseOut
                ) { v.alpha = 1 }
            }
            UIView.animate(
                withDuration: 0.2, delay: 0.21,
                options: .curveEaseOut
            ) { self.nameLabel.alpha = 1 }
        }
    }
}
```

### ⚠️ Critical: Never Use `UIView.animate(delay:)` for Stagger Delays

`UIView.animate(withDuration:delay:)` **immediately sets model-layer values to the final state**. During the delay period, the presentation layer shows the model value (the final position), not the prepared state. The view appears at its destination instantly — the slide-in becomes invisible.

```swift
// ❌ Card appears at final position during delay — slide-in invisible
func animateEntrance(delay: TimeInterval) {
    UIView.animate(withDuration: 0.4, delay: delay, ...) {
        self.card.transform = .identity  // model layer set NOW
    }
}

// ✅ Task.sleep preserves model layer at prepared state until animation starts
func animateEntrance(delay: TimeInterval) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(delay))
        UIView.animate(withDuration: 0.4, delay: 0, ...) {
            self.card.transform = .identity
        }
    }
}
```

This applies to **any** animation where the view must remain in a non-default state during a delay (off-screen position, scaled down, rotated). Short delays (<0.1s) may be unnoticeable; longer delays make the artifact obvious.

### Why Not Other Lifecycle Hooks?

| Hook | `visibleCells` | Issue |
|------|---------------|-------|
| `viewDidLoad` | Empty | Layout hasn't run; cells don't exist |
| `viewWillAppear` | Empty | Same — even with `layoutIfNeeded()` it's a hack |
| `viewDidAppear` | ✅ Available | Works but fires after push ends — feels late |
| `willDisplay` | N/A (per-cell) | ✅ Best — fires exactly when each cell appears |

`willDisplay` + `transitionCoordinator.transitionDuration` as base delay = animation starts right when the push transition ends, no lifecycle timing hacks.

### Timing Reference

| Element | Value |
|---------|-------|
| Base delay | `transitionCoordinator.transitionDuration` (~0.35s) |
| Per-item stagger | 0.1s |
| Card slide-in | 0.4s spring (damping 0.82, velocity 0.3) |
| Inner content cascade | 0.18s per element, 0.07s gap |
| Text fade-in | 0.2s, starts 0.21s after card lands |

## Transform-Safe Positioning

When a view may receive a `CGAffineTransform` (scale, rotate, translate), its parent **must not** use `frame` to position it. `frame` is a derived property computed from `bounds` + `center` + `transform`. Setting `frame` on a view with a non-identity transform produces undefined results — UIKit reverse-computes bounds/center and the values drift.

This bites hardest when a layout pass fires during an animated transform (scroll, intrinsic content size invalidation, device rotation).

```swift
// ❌ frame + transform = drift
override func layoutSubviews() {
    super.layoutSubviews()
    for (subview, size, origin) in items {
        subview.frame = CGRect(origin: origin, size: size)
        // If subview.transform != .identity → bounds/center are wrong
    }
}

// ✅ bounds + center are independent of transform
override func layoutSubviews() {
    super.layoutSubviews()
    for (subview, size, origin) in items {
        subview.bounds = CGRect(origin: .zero, size: size)
        subview.center = CGPoint(
            x: origin.x + size.width / 2,
            y: origin.y + size.height / 2
        )
    }
}
```

**Rule**: Any custom layout container whose children may use transforms (press animations, entrance animations, drag-to-reorder) → always position with `bounds` + `center`, never `frame`.

Auto Layout is immune — it sets `bounds` and `center` internally.

## Summary

| Scenario | Duration | Curve |
|----------|----------|-------|
| Alpha fade (show/hide) | 0.1s | `.curveLinear` |
| Transitions (push, present, layout) | Case-dependent | `.curveLinear` |
| Staggered entrance (collection cells) | 0.4s slide + cascade | Spring (damping 0.82) |
| Expand height (subview-based) | 0.4s | Spring (damping 0.85) |
| Expand content (stagger) | 0.3s each, 0.04s gap | Spring (damping 0.8) |
| Collapse content (subview-based) | 0.15s | `.curveEaseIn` |
| Collapse height (subview-based) | 0.3s | Spring (damping 0.9) |
| Text expand (constraint + clip) | 0.4s | Spring (damping 0.85) |
| Text collapse (constraint + clip) | 0.3s | Spring (damping 0.9) |
| Spring | Only when explicitly requested | Spring |
