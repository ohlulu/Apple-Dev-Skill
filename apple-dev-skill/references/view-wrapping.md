# View Wrapping & Container Patterns

## Core Principle

When a view needs padding inside a `UIStackView`, wrap it in a container with edge insets rather than adding spacing/margin hacks. Extract the wrapping into a reusable extension to eliminate the repeated 6-8 line boilerplate of create → addSubview → translatesAutoresizing → pin four anchors.

## The `wrapped(insets:)` Extension

```swift
extension UIView {
    func wrapped(insets: UIEdgeInsets = .zero) -> UIView {
        let container = UIView()
        container.addSubview(self)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: insets.right),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: insets.bottom),
        ])

        return container
    }
}
```

The container is a plain `UIView` with clear background. The receiver is pinned on all four sides with the given insets. The container derives its intrinsic size from the content — works with `systemLayoutSizeFitting` and self-sizing cells.

## Usage

### Stack View Section Padding

The most common use: adding per-section insets inside a vertical `UIStackView`.

```swift
// Before — 8 lines per section
let wrapper = UIView()
wrapper.addSubview(vStack)
vStack.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    vStack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
    vStack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
    vStack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
    vStack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12),
])
contentStack.addArrangedSubview(wrapper)

// After — 1 line
contentStack.addArrangedSubview(
    vStack.wrapped(insets: UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20))
)
```

### Background Decoration

Wrap content first, then style the container:

```swift
let segBg = segStack.wrapped(insets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))
segBg.backgroundColor = .systemGray6
segBg.layer.cornerRadius = 8
```

### Composing with Decoration Helpers

Build screen-specific helpers that combine `wrapped(insets:)` with decoration (dividers, backgrounds):

```swift
private static let sectionInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)

private func makeSectionWrapper(for content: UIView) -> UIView {
    let wrapper = content.wrapped(insets: Self.sectionInsets)

    let divider = UIView()
    divider.backgroundColor = .separator
    divider.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(divider)
    NSLayoutConstraint.activate([
        divider.topAnchor.constraint(equalTo: wrapper.topAnchor),
        divider.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
        divider.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        divider.heightAnchor.constraint(equalToConstant: 1),
    ])

    return wrapper
}

// Usage — one line per section
contentStack.addArrangedSubview(makeSectionWrapper(for: quantityStack))
contentStack.addArrangedSubview(makeSectionWrapper(for: discountStack))
contentStack.addArrangedSubview(makeSectionWrapper(for: summaryStack))
```

The section-specific helper stays in the view controller. The generic `wrapped(insets:)` stays in a shared extension.

## When to Use

| Scenario | Use `wrapped(insets:)` | Use manual wrapper |
|---|---|---|
| Single content view + edge insets | ✅ | |
| Content + background color/corner radius | ✅ then style the container | |
| Multiple sibling subviews inside container | | ✅ — `wrapped` is one-content-only |
| Content not pinned on all four sides (e.g., centered) | | ✅ — custom constraints needed |
| Container needs gesture recognizers or interaction | ✅ then add to the returned container | |

## Anti-Patterns

### ❌ Spacing Hacks Instead of Wrapping

```swift
// Don't fake padding with stack spacing or spacer views
contentStack.spacing = 20  // applies uniformly — can't vary per section
contentStack.addArrangedSubview(UIView())  // spacer hack — fragile
```

### ❌ Over-Abstracting

Don't build a DSL or builder chain. `wrapped(insets:)` is one method that does one thing. Composition with decoration helpers handles the rest.
