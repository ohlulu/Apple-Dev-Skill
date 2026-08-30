# Shadow and Clipping

## Core Rule

A `CALayer` shadow is drawn **outside** the layer's bounds. If **any ancestor** in the view hierarchy sets `clipsToBounds = true` (or `layer.masksToBounds = true`), the shadow is silently clipped — no warning, no error.

## UICollectionViewCell Default

`UICollectionViewCell.contentView.clipsToBounds` defaults to `true`. This means any shadow applied to a subview inside `contentView` is invisible unless you explicitly opt out:

```swift
override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false
    // …
}
```

`UITableViewCell.contentView` has the same default behavior.

## Ancestor Chain Check

When a shadow doesn't appear, check the **entire** ancestor chain from the shadowed view up to the scroll view:

```
UICollectionView         clipsToBounds = true (expected — scroll clipping)
  └─ Cell                clipsToBounds = ?
       └─ contentView    clipsToBounds = ?   ← often the culprit
            └─ CardView  clipsToBounds = false, shadow configured
```

## Shadow Needs Space

A shadow with `shadowOffset = (0, 4)` and `shadowRadius = 12` extends roughly 16pt below the layer and 12pt on each side. The shadowed view must have enough margin from its clipping ancestor's bounds for the shadow to be visible.

Two approaches:
1. **Inset the card** from `contentView` edges (e.g., 16pt), so the shadow falls within `contentView` bounds — no need to disable clipping.
2. **Disable clipping** on the cell and `contentView`, let the shadow extend beyond bounds.

Approach 2 is simpler when section `contentInsets` already provide the margin.

## Deferred Visual Initialization

When a view separates structural setup (`init`) from visual theming (`applyTheme`), the view starts with no background color. If `applyTheme` is not called before the first render, the view is transparent.

Always either:
- Set a default `backgroundColor` in `init`, or
- Call `applyTheme()` at the end of `init`

For reusable cells, also call `applyTheme()` at the end of `configure(with:)` to cover the reconfiguration path.

## Shadow + Corner Radius: Parent/Child Split

When a view needs **both** a shadow and rounded corners, they cannot coexist on the same layer. `clipsToBounds = true` (required for corner radius) clips the shadow. `clipsToBounds = false` (required for shadow) disables corner radius clipping.

**Solution: two layers.**

```swift
// Parent: owns the shadow, does NOT clip
let container = UIView()
container.clipsToBounds = false
container.layer.shadowColor = UIColor.black.cgColor
container.layer.shadowOpacity = 0.2
container.layer.shadowOffset = CGSize(width: 0, height: 4)
container.layer.shadowRadius = 8

// Child: owns the corner radius, DOES clip
let content = UIImageView(image: icon)
content.layer.cornerRadius = 16
content.clipsToBounds = true
container.addSubview(content)
// Pin content edges to container edges
```

## CALayer Frame Ownership — Each View Manages Its Own Layers

When adding `CAGradientLayer`, `CAShapeLayer`, or other sublayers to a view, **the owning view must update the layer's frame in its own `layoutSubviews`** — not a parent or grandparent.

### The bug

A cell's `layoutSubviews` reads a deeply nested subview's bounds and sets a sublayer frame:

```swift
// ❌ Cell's layoutSubviews — clipView is 3+ levels deep
override func layoutSubviews() {
    super.layoutSubviews()
    gradientLayer.frame = clipView.bounds  // zero on first display!
}
```

`super.layoutSubviews()` resolves constraints for the cell's direct subviews, but **deeply nested views may not have their bounds resolved yet**. The layer frame is set to `.zero`, and the gradient is invisible. Navigating away and back "fixes" it because the cell is reused with pre-existing bounds.

This is especially deceptive: the second display always works, making the bug appear intermittent or timing-related.

### The fix

Create a UIView subclass that owns the layer and updates it in its own `layoutSubviews`:

```swift
// ✅ Each view manages its own layers
private final class GradientBackgroundView: UIView {
    let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(gradientLayer)
        // Set constant properties here (colors, startPoint, etc.)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds  // always correct — this view's own bounds
    }
}
```

When Auto Layout sets this view's frame, its `layoutSubviews` fires and the layer frame is immediately correct — regardless of how deep it sits in the hierarchy.

### Rule of thumb

- **Constant layer properties** (colors, startPoint, endPoint, cornerRadius): set in `init` or a `configure` method.
- **Frame-dependent properties** (frame, path, shadowPath): set in the **owning view's** `layoutSubviews`.
- **Never reach down** from a parent's `layoutSubviews` to read a child's bounds for layer sizing.

## Layer Border Draws Above All Sublayers

`layer.borderWidth` / `borderColor` are composited **on top of every sublayer** — and every subview is a sublayer. Any subview that overlaps the border path gets the border line drawn straight through it. Typical victims: a floating "Recommended" pill straddling a card's top edge, a close button hanging off a corner, an avatar overlapping a ring.

Rule: when any subview overlaps a bordered view's edge, do not put the border on the container's own layer. Move it to a dedicated border subview pinned to the container's bounds and ordered **below** the overlapping subview; keep `cornerRadius` on the container for the background fill.

```swift
let borderView = UIView()
borderView.isUserInteractionEnabled = false
borderView.layer.cornerRadius = Radius.lg   // match the container
borderView.layer.cornerCurve = .continuous
borderView.layer.borderWidth = 2
addSubview(borderView)          // added before the badge → renders below it
// pin borderView to all four edges; badge is added later, on top
```

State changes (selection color) then target `borderView.layer.borderColor` instead of `layer.borderColor`.

## UILabel `backgroundColor` Is Not Clipped by `cornerRadius`

`UIView.backgroundColor` is normally rendered through `layer.backgroundColor`, which Core Animation clips to `cornerRadius` automatically. **`UILabel` is the exception.** When you set `backgroundColor` on a UILabel, the colour is painted into the layer's **contents bitmap** (alongside the text glyphs), not assigned to `layer.backgroundColor`. Core Animation only clips contents when `masksToBounds = true`.

Result: a UILabel with `layer.cornerRadius > 0` and `masksToBounds = false` (the configuration you need for a soft shadow) renders the fill as a **sharp rectangle**, no matter what corner radius you set.

### Symptom

A pill / badge / chip built as a UILabel with `backgroundColor` + `cornerRadius` + soft shadow — shape is square, shadow is square, cornerRadius appears to have no effect at all.

```swift
// ❌ Looks like a sharp rectangle, never rounds
let badge = UILabel()
badge.text = "1"
badge.backgroundColor = .systemBlue       // painted into contents
badge.layer.cornerRadius = 10              // does not clip contents
badge.layer.masksToBounds = false          // required for shadow
badge.layer.shadowOpacity = 0.15
```

Enabling `masksToBounds = true` would clip the fill rounded, but would also clip the shadow away. Neither combination gives "rounded fill + soft shadow" on a UILabel.

### Fix: wrap the label in a plain `UIView` container

Plain `UIView` honours `layer.backgroundColor`, which **is** clipped by `cornerRadius` without `masksToBounds = true`. Put the shape and shadow on the container, let the label render only the text.

```swift
// ✅ Container owns shape + shadow; label is text only
private final class QtyBadgeView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBlue           // via layer.backgroundColor → clipped by cornerRadius
        layer.cornerRadius = 10
        layer.masksToBounds = false             // shadow can extend outside
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2

        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = .clear          // never give the label its own fill
        addSubview(label)
        // pin label edges with padding constraints
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2          // perfect capsule at any width
        layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }
}
```

Setting `shadowPath` is a correctness *and* a performance fix: without it Core Animation re-derives the shadow shape from the layer's alpha channel every frame, which shows up as shadows flickering during scroll. A cached path removes the per-frame work.

### Rule of thumb

- **Need a coloured fill with `cornerRadius`?** Use a plain `UIView` container. Never paint the fill via `UILabel.backgroundColor`.
- The same trap applies to any view whose `-drawRect:` paints its own background: custom `UIView` subclasses that fill themselves in `draw(_:)`, some `UIControl` subclasses, and any view rendering through `drawsAsynchronously`.
- For pills, badges, chips, status tags — default to `UIView` container + inner UILabel from day one. Don't try to make UILabel both the shape and the text.

## Sheet Presentation: Double-Background Color Shift (iOS 26+)

When a view controller is presented as a sheet (`.automatic` / `.pageSheet`), iOS 26 inserts a `UIDropShadowView` with rounded corners and material compositing between the presenting and presented view controllers.

If a subview (e.g., `UICollectionView`) has the **same opaque backgroundColor** as the root view, two opaque layers of the same color are composited through the sheet's material pipeline. GPU floating-point precision and color space conversion (sRGB ↔ Display P3) produce a **subtle but visible color seam** at the boundary where the subview starts.

```
❌ Two opaque layers — visible seam
┌─ Sheet material ──────────────┐
│  ┌─ VC.view (theme.bg) ──────┐│
│  │  Search bar area           ││  ← one layer
│  │  ┌─ CollectionView ─────┐ ││
│  │  │  (theme.bg, opaque)  │ ││  ← two layers composited
│  │  └──────────────────────┘ ││
│  └────────────────────────────┘│
└────────────────────────────────┘

✅ Single background layer — no seam
│  │  ┌─ CollectionView ─────┐ ││
│  │  │  (.clear)             │ ││  ← root view shows through
│  │  └──────────────────────┘ ││
```

### Fix

Set scroll view / collection view / table view `backgroundColor = .clear` and let the VC's root view be the **sole background provider**:

```swift
private func applyTheme() {
    ThemeApplier.apply(to: self)          // sets view.backgroundColor
    collectionView.backgroundColor = .clear // ← single background source
}
```

### When this bites

- Sheet-presented screens with a search bar above a scroll view (the seam appears at the search bar / list boundary)
- Any modal with subviews that duplicate the root view's background color
- More visible on P3 displays and with non-neutral theme colors (warm grays, tinted backgrounds)

### Does NOT affect

- Full-screen presentations (no sheet material layer)
- Views where the scroll view intentionally has a different background color
- Pre-iOS 26 (no `UIDropShadowView` in the hierarchy)

