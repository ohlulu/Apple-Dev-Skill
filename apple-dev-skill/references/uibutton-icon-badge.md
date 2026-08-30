# UIButton as Icon Badge

Small circular icon badges (camera overlay on avatar, status dot, edit pencil) are common. UIButton is the right host — it provides hit testing, accessibility traits, and highlight state — but the wrong image API will shift the icon off-center.

## The Problem: `setImage` and `.system` Type

```swift
// ❌ Icon renders off-center — two compounding issues
let badge = UIButton(type: .system)
badge.setImage(UIImage(named: "camera"), for: .normal)
badge.backgroundColor = theme.accent
badge.layer.cornerRadius = badgeSize / 2
```

1. **`UIButton(type: .system)`** applies an internal content inset and tint behavior that cannot be fully zeroed out. Even with `contentEdgeInsets = .zero`, the system type reserves padding for the image.
2. **`setImage(_:for:)`** feeds the image into UIButton's image layout engine, which centers the image in the *content area* (after insets), not the button's bounds. For tiny badges (< 30pt) the 2–4pt offset is clearly visible.

Setting `UIButton.Configuration` makes it worse — Configuration has its own `contentInsets` defaults (non-zero) and ignores legacy inset properties entirely.

## The Fix: `.custom` Type + Icon as Subview

Bypass UIButton's image layout entirely. Use the button for hit testing and highlight; use a plain `UIImageView` subview for the icon.

```swift
// ✅ Icon is pixel-perfect centered via Auto Layout
let badge = UIButton(type: .custom)
badge.clipsToBounds = true
badge.backgroundColor = theme.accent

let icon = UIImageView()
icon.translatesAutoresizingMaskIntoConstraints = false
icon.contentMode = .scaleAspectFit
icon.image = UIImage(named: "camera")?.withRenderingMode(.alwaysTemplate)
icon.tintColor = .white
icon.isUserInteractionEnabled = false  // let touches pass through to button
badge.addSubview(icon)

let inset: CGFloat = round(badgeSize * 0.24)
NSLayoutConstraint.activate([
    icon.topAnchor.constraint(equalTo: badge.topAnchor, constant: inset),
    icon.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: inset),
    icon.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -inset),
    icon.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -inset),
])
```

Set `badge.layer.cornerRadius` in `layoutSubviews` (or after constraints resolve), not at creation time — the badge's bounds aren't final until Auto Layout has run, so a radius computed from `badgeSize` at init time can be stale if the badge is later resized.

### Why `.custom` Instead of `.system`

| Aspect | `.system` | `.custom` |
|--------|-----------|-----------|
| Tint override | Applies tint to all subviews | No automatic tint |
| Content insets | Internal padding, not fully removable | Zero by default |
| Highlight animation | Built-in alpha fade | Manual (see below) |
| Safe for subview layout | No — system layout engine repositions content | Yes — subviews stay where you put them |

### Highlight Animation

`UIButton(type: .custom)` has no default highlight feedback. Add it via `touchDown` / `touchUp` target actions:

```swift
badge.addTarget(self, action: #selector(badgeTouchDown), for: .touchDown)
badge.addTarget(self, action: #selector(badgeTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

@objc private func badgeTouchDown() {
    UIView.animate(withDuration: 0.1) { self.badge.alpha = 0.5 }
}

@objc private func badgeTouchUp() {
    UIView.animate(withDuration: 0.15) { self.badge.alpha = 1.0 }
}
```

This replicates the `.system` type's fade but without its layout side effects.

## When This Pattern Applies

- Badge diameter < 44pt (small enough that inset offsets are visible)
- Icon must be visually centered in a circular or rounded-rect background
- The button has a `backgroundColor` + `cornerRadius` (not using Configuration's filled/tinted styles)

For standard-sized buttons (≥ 44pt) where you want Configuration's built-in styles, use `UIButton.Configuration` normally — the inset issue is negligible at that size. See [uibutton-configuration](uibutton-configuration.md) for that API.

