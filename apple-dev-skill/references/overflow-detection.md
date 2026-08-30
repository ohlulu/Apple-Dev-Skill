# Content Overflow Detection

## Core Principle

Never pre-calculate whether content fits by estimating widths or summing constants. Estimation drifts: font rendering, button insets, and dynamic type all introduce errors that produce false positives or false negatives.

Use actual layout as the single source of truth — show all content first, then measure whether it wrapped.

## Two-Pass Layout Pattern

The standard approach for dynamic content that may or may not overflow its container:

### Pass 1 — Show Everything

Configure the view with **all** content visible. Let Auto Layout + the container (FlowLayoutView, UIStackView, etc.) determine natural size.

```swift
func configure(with values: [UnitValue]) {
    flowView.removeAllItems()
    collapsibleViews = []

    for (i, value) in values.enumerated() {
        let btn = makeValueButton(value)
        flowView.addSubview(btn)
        if i >= 1 { collapsibleViews.append(btn) }
    }

    // No chevron yet — let layout decide
    chevronButton.isHidden = true
    pendingOverflowCheck = values.count > 1
}
```

### Pass 2 — Detect Overflow After Layout

In `layoutSubviews`, after the container has real dimensions, check whether content actually wrapped:

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    guard pendingOverflowCheck, flowView.bounds.width > 100 else { return }
    pendingOverflowCheck = false

    // Force child to complete internal layout
    flowView.setNeedsLayout()
    flowView.layoutIfNeeded()

    // Compare actual content height vs single-line height
    let singleLineHeight = ValueButton.measuredHeight
    let actualHeight = flowView.intrinsicContentSize.height

    if actualHeight > singleLineHeight + 2 {
        DispatchQueue.main.async { [weak self] in
            self?.onOverflowDetected?()
        }
    }
}
```

### Key Details

| Detail | Why |
|--------|-----|
| `flowView.bounds.width > 100` guard | Skips the first layout pass where width is 0 or wrong |
| `flowView.layoutIfNeeded()` before measuring | Forces child view to arrange items with real width |
| `intrinsicContentSize.height` not `bounds.height` | `bounds.height` is constraint-driven; `intrinsicContentSize` is content-driven |
| `DispatchQueue.main.async` for callback | Avoids layout-during-layout when the callback triggers a rebuild |
| `pendingOverflowCheck` flag | Prevents re-checking after collapse — only runs once per configure |

## Mutually Exclusive Trailing Constraints

When the overflow indicator (chevron, "more" button) should only appear when content overflows, its space affects available width. Use two constraints, only one active at a time:

```swift
// Without chevron — flow gets full width
flowTrailingToEdge = flowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)

// With chevron — flow stops before chevron
flowTrailingToChevron = flowView.trailingAnchor.constraint(equalTo: chevronButton.leadingAnchor, constant: -4)

// Default: no chevron
flowTrailingToEdge.isActive = true
flowTrailingToChevron.isActive = false
```

This avoids the catch-22 where content fits without the chevron but overflows with it. Pass 1 uses the wider constraint; the chevron constraint only activates after overflow is confirmed.

## Anti-Patterns

### ❌ Width Estimation

```swift
// Fragile — drifts with font changes, dynamic type, localization
let nameWidth = (text as NSString).size(withAttributes: attrs).width
let available = screenWidth - fixedPadding - nameWidth
let fits = totalValueWidth <= available
```

Font metrics from `NSString.size(withAttributes:)` don't account for UIButton.Configuration padding, contentInsets, or layout margins. The only reliable measurement is the one Auto Layout performs.

### ❌ Static `maxVisibleItems` Constants

```swift
private static let maxVisibleValues = 2  // ❌ arbitrary, device-dependent
```

What fits on an iPhone 17 Pro Max won't fit on an SE. Use actual layout, not item count thresholds.
