# Self-Sizing Patterns

## Core Principle

Never manually sum magic numbers to compute a view's height. If every subview has a complete vertical constraint chain, Auto Layout already knows the answer — ask it with `systemLayoutSizeFitting`.

Hardcoded height calculations are fragile: they silently drift when padding, font size, or spacing changes. The layout engine is the single source of truth.

## `systemLayoutSizeFitting` — The Universal Measuring Tool

Given a root view (typically a `UIStackView`) with a complete constraint chain, compress it at a fixed width to get the intrinsic height:

```swift
let fittingSize = contentStack.systemLayoutSizeFitting(
    CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
)
```

- **`.required` horizontal** — width is fixed; content wraps within it.
- **`.fittingSizeLevel` vertical** — compress to the smallest height that satisfies all constraints.

This is the same mechanism UIKit uses internally for self-sizing table/collection cells.

## Modal / Popover `preferredContentSize`

For `.formSheet`, `.popover`, or any presentation that reads `preferredContentSize`:

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    buildUI()        // assemble view hierarchy + constraints
    populateData()   // fill labels, show/hide conditional sections
    updatePreferredContentSize()
}

private func updatePreferredContentSize() {
    let width: CGFloat = 400
    let insets: CGFloat = 16 // contentStack edge insets × 2
    let fittingSize = contentStack.systemLayoutSizeFitting(
        CGSize(width: width - insets, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    )
    preferredContentSize = CGSize(width: width, height: fittingSize.height + insets)
}
```

### Why `viewDidLoad`, not `init`?

The view hierarchy doesn't exist in `init`. Measuring requires constraints to be installed. Set `preferredContentSize` after `buildUI()` — UIKit reads it during presentation layout, which happens after `viewDidLoad`.

### Dynamic Re-sizing

If content changes after presentation (e.g., toggling a discount section), call `updatePreferredContentSize()` again. The presentation controller animates to the new size automatically.

## Prerequisite: Complete Vertical Constraint Chain

`systemLayoutSizeFitting` only works when every subview in the vertical axis is anchored top-to-bottom without gaps. Common pitfalls:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Returns 0 or near-zero height | Root view has no top/bottom anchoring | Pin content to the measuring container's edges |
| Returns `CGFloat.greatestFiniteMagnitude` | An unconstrained view with no intrinsic height | Add explicit height or pin both top and bottom |
| Taller than expected | Hidden views still contribute to stack spacing | Use `UIStackView` — it collapses hidden arranged subviews |

### Quick Checklist

- Every subview pins **top** and **bottom** (directly or via stack view).
- Views with no intrinsic content size have an explicit height constraint.
- `UIStackView` is preferred — it handles hiding/showing arranged subviews and spacing automatically.
- Buttons using `UIButton.Configuration` have intrinsic height from content insets. Custom buttons need a min-height constraint (`greaterThanOrEqualToConstant`).

## Self-Sizing Table / Collection Cells

The same principle, different entry point. UIKit calls `systemLayoutSizeFitting` on the cell's `contentView` internally when you opt in:

```swift
tableView.rowHeight = UITableView.automaticDimension
tableView.estimatedRowHeight = 60
```

For collection view, use `NSCollectionLayoutSize` with `.estimated()`:

```swift
let itemSize = NSCollectionLayoutSize(
    widthDimension: .fractionalWidth(1.0),
    heightDimension: .estimated(80)
)
```

The cell must have a complete vertical constraint chain inside `contentView`. Same rules apply — no gaps, no unconstrained heights.

## Anti-Patterns

### ❌ Hardcoded Height Arithmetic

```swift
// Fragile — drifts silently when any section changes
func computeHeight() -> CGFloat {
    var h: CGFloat = 80  // header
    h += CGFloat(items.count) * 60  // rows
    h += 120  // footer
    return h
}
```

### ❌ `intrinsicContentSize` Override for Layout Measurement

Don't override `intrinsicContentSize` just to report a measured height. That property is for views with a natural content size (labels, images). For containers, use `systemLayoutSizeFitting`.

### ❌ Measuring Before View Hierarchy Exists

```swift
init() {
    super.init(nibName: nil, bundle: nil)
    // ❌ No constraints installed yet — measurement is meaningless
    preferredContentSize = CGSize(width: 400, height: measure())
}
```

## Summary

| Scenario | Technique |
|----------|-----------|
| Modal / popover height | `systemLayoutSizeFitting` in `viewDidLoad` → `preferredContentSize` |
| Table cell height | `automaticDimension` + complete constraint chain in `contentView` |
| Collection cell height | `.estimated()` layout dimension + complete constraint chain |
| Embedded child controller | `systemLayoutSizeFitting` on child's view → height constraint on container |
| Wizard / multi-step card with size-changing children | See [step-transition-sizing.md](step-transition-sizing.md) — measurement + explicit container height + outgoing-child decoupling |
| Any "how tall is this?" question | `systemLayoutSizeFitting` with fixed width, compressed height |
