# Auto Layout Spacing and Distribution

## Core Principle

Auto Layout's Cassowary solver resolves **all constraints simultaneously** in a single pass. There is no "lay out content first, then distribute remaining space" phase — unlike CSS Flexbox. Design spacing strategies around this reality.

## UIStackView Spacing: The Primary Tool

### Fixed Gaps Between Sections

Use `setCustomSpacing(_:after:)` for consistent gaps that don't vary with screen size:

```swift
let stack = UIStackView(arrangedSubviews: [header, table, pills, cta])
stack.axis = .vertical
stack.spacing = 0  // base spacing off, control each gap individually

stack.setCustomSpacing(20, after: header)  // header → table
stack.setCustomSpacing(20, after: table)   // table → pills
stack.setCustomSpacing(16, after: pills)   // pills → CTA
```

This is predictable on all screen sizes. Prefer this over spacer views.

### When Fixed Gaps Leave Extra Space

Pin the content group to the **top** and the footer to the **bottom** independently. The gap between CTA and footer absorbs the variable space naturally:

```swift
// Content stack: pinned to top
contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40)
// no bottom constraint on contentStack

// Footer: pinned to bottom
footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
```

On shorter screens, the gap shrinks. On taller screens, it grows. No constraint conflicts.

## Why CSS Flex Spacers Don't Work in Auto Layout

### The CSS Model

```css
.spacer { flex: 1; min-height: 4px; max-height: 20px; }
```

CSS Flexbox has a **two-phase** solver:
1. Lay out flex-shrink: 0 items at their intrinsic size.
2. Distribute remaining space among flex items proportionally, capped by min/max.

The `max-height: 20px` is a **hard cap** that the flex algorithm respects before distribution.

### The Auto Layout Model

The naive translation:

```swift
// ❌ DON'T — this creates unsatisfiable constraints
let spacer = UIView()
spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true   // required
spacer.heightAnchor.constraint(lessThanOrEqualToConstant: 20).isActive = true     // required
outerStack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor).isActive = true // required
```

If `contentHeight + 3 × 20 < availableHeight`, the solver has no valid solution:
- Each spacer is capped at 20pt (required constraint).
- The stack must reach the bottom (required constraint).
- Remaining space has nowhere to go.

The solver **breaks the lowest-priority constraint** to find a feasible solution. When all are `.required` (1000), the choice is **implementation-defined** — the spacers grow beyond 20pt unpredictably.

### If You Must Have Flexible Spacers

Lower the max-height priority so it yields gracefully:

```swift
let spacer = UIView()
spacer.setContentHuggingPriority(.init(1), for: .vertical)
spacer.setContentCompressionResistancePriority(.init(1), for: .vertical)

let min = spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 4)
min.priority = .required  // always at least 4pt

let preferred = spacer.heightAnchor.constraint(equalToConstant: 16)
preferred.priority = .init(1)  // lowest — stretch or compress freely

// Do NOT set a max-height constraint. Let content hugging handle it.
```

And pin the outer container **bottom** at `.defaultHigh` (750), not `.required`:

```swift
let bottom = outerStack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
bottom.priority = .defaultHigh  // can break if content overflows
```

But this is complex and fragile. **`setCustomSpacing` + separate top/bottom pinning is almost always better.**

## Decision Table

| Scenario | Approach |
|----------|----------|
| Consistent gaps between sections | `setCustomSpacing` on UIStackView |
| Footer always at bottom, content at top | Pin independently — no spacer needed |
| Vertically centered content | `centerYAnchor` constraint at `.defaultHigh` |
| Equal distribution of items | `UIStackView.distribution = .equalSpacing` |
| Proportional space (⅓ / ⅔ split) | `UILayoutGuide` with multiplier constraints |
| Mockup uses CSS flex spacers | **Do not translate literally.** Use fixed gaps or independent pinning |

## Common Pitfalls

### ❌ `distribution = .fillEqually` for Variable-Height Content

`.fillEqually` forces all arranged subviews to the same height. Use `.fill` (default) and let intrinsic content sizes determine heights.

### ❌ Negative Spacing to Overlap Views

UIStackView spacing is additive. Negative values create visual overlap but cause ambiguous layouts. Use `transform` or a custom container instead.

## Shadow + Corner Radius (Cross-Reference)

When building card-like layouts with shadows, remember the parent/child split rule (shadow on the parent with `clipsToBounds = false`, corner radius on the child with `clipsToBounds = true`) — see [shadow-and-clipping](shadow-and-clipping.md) for the full pattern. This is often needed alongside spacing decisions because cards with shadows require margin space from their clipping ancestor. Use `setCustomSpacing` or wrapper view insets to provide that margin.
