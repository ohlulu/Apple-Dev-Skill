# Vertical Alignment

## Core Principle

When aligning text of different sizes on the same row, choose **one** strategy and verify the prerequisite holds. The two options — centerY and baseline — produce visibly different results, and each breaks in specific contexts.

## CenterY Alignment

Aligns the geometric vertical center of each element. Best for: icon + text, mixed-height elements where text size is similar, or when the design intent is "everything floats at the same midline."

```swift
nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor)
pillFlow.topAnchor.constraint(
    equalTo: iconView.centerYAnchor,
    constant: -PillButton.measuredHeight / 2
)
```

### Pitfall: Magic Offsets

Don't hardcode `flowView.top = icon.top + 6` assuming pill height is 24pt. If the actual pill height differs (wrong font, extra Configuration padding, dynamic type), the offset is wrong and the misalignment is silent.

**Fix**: Measure the real height (see below) and compute offset from it.

## Baseline Alignment

Aligns the text baseline (where letters sit). Best for: mixed-size text that should read as a single line of prose — e.g., a 15pt label next to 13pt values.

```swift
nameLabel.firstBaselineAnchor.constraint(equalTo: valueLabel.firstBaselineAnchor)
```

### Prerequisite: Full Auto Layout Hierarchy

`firstBaselineAnchor` propagation relies on UIKit traversing the view tree via `forFirstBaselineLayout` to find the leaf view that reports its baseline. **Every view in the chain must use Auto Layout for internal positioning.**

If a container uses manual frame layout (`layoutSubviews` with `subview.frame = ...`), child frames are `CGRect.zero` when Auto Layout resolves baseline constraints. The reported baseline is wrong.

| Container type | Baseline works? |
|---------------|----------------|
| UIStackView | ✅ Yes |
| Auto Layout subviews | ✅ Yes |
| Manual frame layout (`layoutSubviews`) | ❌ No — child frames not set at resolve time |
| UICollectionView / UITableView cells | ✅ Yes (within contentView) |

### Common Failure Mode

```swift
// FlowLayoutView positions children in layoutSubviews (manual frames)
override var forFirstBaselineLayout: UIView {
    subviews.first ?? self  // returns a chip button at frame (0,0,0,0)
}

// ❌ Baseline = chip.frame.minY(0) + chip.titleLabel.frame.minY(0) + ascender
//    Missing: contentInsets.top offset, actual chip position in container
nameLabel.firstBaselineAnchor.constraint(equalTo: flowView.firstBaselineAnchor)
```

The constraint resolves with garbage values. The label shifts to a wrong position.

## Measure, Don't Calculate

When aligning with views whose intrinsic height depends on UIKit internals (UIButton.Configuration padding, dynamic type, attributed strings), **measure a real instance** instead of summing `inset + lineHeight + inset`:

```swift
static let measuredHeight: CGFloat = {
    let btn = UIButton(type: .system)
    var cfg = UIButton.Configuration.plain()
    cfg.title = "X"
    cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
    cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var a = incoming
        a.font = .systemFont(ofSize: 13, weight: .semibold)
        return a
    }
    btn.configuration = cfg
    return btn.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
}()
```

This captures all internal UIKit metrics (Configuration defaults, minimum hit targets, text attachment padding) that manual arithmetic misses.

### When to Use

- Any `UIButton.Configuration` button — internal padding is opaque.
- Attributed strings with mixed fonts or attachments.
- Views with `dynamic type` that change height at runtime.

### When Manual Arithmetic Is Fine

- Plain `UILabel` with a known fixed font — `font.lineHeight` is reliable.
- `UIView` with explicit height constraints — the constraint IS the height.
