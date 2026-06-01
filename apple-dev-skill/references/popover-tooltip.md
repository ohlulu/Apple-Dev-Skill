# Popover Tooltip — Layout & Sizing

Lightweight info tooltips presented via `UIPopoverPresentationController`.
Covers the safe-area centering trap, iPhone adaptation, sizing, and arrow positioning.

## Safe Area Centering Trap

**The problem**: The popover arrow occupies space *outside* the safe area.
Pinning content to `view.topAnchor` / `view.bottomAnchor` causes text to
appear shifted toward the arrow side — the padding on the arrow side is
eaten by the arrow, while the opposite side gets full padding.

```
┌─────────────────┐
│▼ arrow (unsafe) │  ← view.topAnchor is here
│ Text starts     │  ← text too close to top
│ here            │
│                 │  ← bottom has full padding
└─────────────────┘
```

**The fix**: Always pin content to `view.safeAreaLayoutGuide`.
The safe area excludes the arrow region, so padding is symmetric.

```swift
// ❌ Text shifted toward arrow
label.topAnchor.constraint(equalTo: view.topAnchor, constant: padding)
label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding)

// ✅ Text centered in the visible bubble
let guide = view.safeAreaLayoutGuide
label.topAnchor.constraint(equalTo: guide.topAnchor, constant: padding)
label.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -padding)
label.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: padding)
label.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: padding)
```

This applies regardless of arrow direction — the safe area insets adjust
dynamically based on which side the arrow is on.

## iPhone Adaptation

By default, `UIPopoverPresentationController` presents as a full-screen
sheet on iPhone. To force compact popover style, implement
`UIPopoverPresentationControllerDelegate`:

```swift
func adaptivePresentationStyle(
    for controller: UIPresentationController,
    traitCollection: UITraitCollection
) -> UIModalPresentationStyle {
    .none
}
```

Set the delegate **before** presenting. The popover presentation controller's
delegate must be assigned before `present(_:animated:)` is called.

## Sizing with `preferredContentSize`

Calculate size from the label's `sizeThatFits`, adding padding.
The padding in `preferredContentSize` must match the constraint constants,
but does **not** need to account for the arrow — the system adds arrow
space on top of `preferredContentSize`.

```swift
let maxWidth: CGFloat = 300
let hPad: CGFloat = 16
let vPad: CGFloat = 14

let textSize = label.sizeThatFits(
    CGSize(width: maxWidth - hPad * 2, height: .greatestFiniteMagnitude)
)
preferredContentSize = CGSize(
    width: min(textSize.width + hPad * 2, maxWidth),
    height: textSize.height + vPad * 2
)
```

### ⚠️ Use `label.sizeThatFits`, NOT `view.systemLayoutSizeFitting`

It is tempting to measure the *container view* with
`systemLayoutSizeFitting(_:withHorizontalFittingPriority:verticalFittingPriority:)`
so the safe-area-anchored constraints "just do the math". Do not.

Why it breaks: the view-level fit runs through your safe-area
constraints, but at viewDidLoad time `safeAreaInsets` may be zero or
stale. The returned height assumes a different chrome state than
layout time, so once the popover actually renders — with real arrow
insets — the content view is taller than the text needs and the
surplus dumps onto one side of the bubble (usually the bottom),
reproducing the *exact* asymmetry the safe-area pinning was meant to
fix.

Measure the label in isolation with a known target width
(`maxWidth - hPad * 2`). This decouples sizing from chrome state and
produces a bubble that hugs the text symmetrically regardless of
arrow direction.

```swift
// ❌ View-level fit — text appears shifted, bubble has extra padding on one side
let target = view.systemLayoutSizeFitting(
    CGSize(width: maxWidth - hPad * 2, height: UIView.layoutFittingCompressedSize.height),
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
)
preferredContentSize = CGSize(
    width: ceil(target.width) + hPad * 2,
    height: ceil(target.height) + vPad * 2
)

// ✅ Label-level fit — symmetric padding on all four sides
let textSize = label.sizeThatFits(
    CGSize(width: maxWidth - hPad * 2, height: .greatestFiniteMagnitude)
)
preferredContentSize = CGSize(
    width: min(ceil(textSize.width) + hPad * 2, maxWidth),
    height: ceil(textSize.height) + vPad * 2
)
```

## Arrow Direction

| Setting | Behavior |
|---------|----------|
| `.up` | Arrow points up; popover below source. Clips if source is near bottom. |
| `.down` | Arrow points down; popover above source. Clips if source is near top. |
| `.any` | System picks best direction based on available space. **Recommended default.** |

Use `.any` unless you have a specific layout reason to constrain direction.

## Tap Target Size

Apple HIG minimum: 44×44pt. For inline info buttons where 44pt feels too
large, 40×40pt is the practical minimum. Never go below — small targets
cause mis-taps and frustrate users.

The visual icon can be smaller (e.g. 18pt) while the button frame remains
40×40pt. UIButton handles hit-testing on the full frame.

## Dismiss Behavior

Add a tap gesture on the popover's view for tap-to-dismiss. The popover
also auto-dismisses on outside taps when using `.popover` presentation style
with `adaptivePresentationStyle` returning `.none`.

## Checklist

- [ ] Content pinned to `safeAreaLayoutGuide` (not `view`)
- [ ] `adaptivePresentationStyle` returns `.none` for iPhone popover
- [ ] `preferredContentSize` calculated via `label.sizeThatFits` (NOT `view.systemLayoutSizeFitting`)
- [ ] Arrow direction `.any` (unless constrained by design)
- [ ] Info button tap target ≥ 40×40pt
- [ ] Delegate assigned before `present()`
