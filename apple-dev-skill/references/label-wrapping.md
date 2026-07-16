# Multiline Label Wrapping in Stack Views

## When to Apply / Not For

- Apply when a `numberOfLines = 0` `UILabel` lives inside (possibly nested) stack views and must wrap instead of truncate.
- NOT for detecting whether content overflowed/wrapped (→ `overflow-detection.md`) and NOT for measuring a container's natural size (→ `self-sizing.md`).

## Icon + Wrapping Label Rows: Hugging Alone Loses the Icon

A horizontal `[fixed icon, wrapping label]` row must set **both** priorities on the icon:

```swift
icon.setContentHuggingPriority(.required, for: .horizontal)
icon.setContentCompressionResistancePriority(.required, for: .horizontal)
```

Why: hugging resists *stretching* and does nothing against *compression*. When the label's text exceeds the row width, something must give — and the label and image view tie at the default 750 compression resistance. The engine breaks the tie arbitrarily, so it can crush the icon to zero width instead of wrapping the label. The symptom looks random: some rows silently lose their icon (and shift left by the icon width) while identical sibling rows keep theirs.

## Width Churn: Self-Syncing `preferredMaxLayoutWidth`

When a wrapping label's ancestor width can settle across layout passes — a preferred-width column inside a scroll view, split-view detail panes, rows rebuilt on state changes — use a self-syncing label instead of a plain `UILabel`:

```swift
final class WrappingLabel: UILabel {
  override func layoutSubviews() {
    super.layoutSubviews()
    if preferredMaxLayoutWidth != bounds.width {
      preferredMaxLayoutWidth = bounds.width   // invalidates intrinsic size
    }
  }
}
```

Why: UIKit's automatic wrap re-measure is effectively one-shot per settle. A label measured as one line while the container was wide keeps that stale single-line height when a later pass narrows the container — the text then truncates ("…") even though `numberOfLines == 0`, and stays wrong across re-displays. Labels that happened to wrap at the wide width look coincidentally correct, which hides the bug in review.

The `!=` guard prevents invalidation loops; the setter triggers `invalidateIntrinsicContentSize()`, so the next pass re-wraps.

**Placement is the point:** the sync must live in the label's *own* `layoutSubviews`. Layout is top-down — an ancestor's `layoutSubviews` runs before deep labels receive their final bounds, and the ancestor is not guaranteed to lay out again when they do. Only the label itself is guaranteed a `layoutSubviews` call after every bounds change.

## Symptom → Cause

| Symptom | Cause | Fix |
|---|---|---|
| Check/leading icon missing from some rows only | icon compressed to 0 in the label-width fight | `.required` horizontal compression resistance on the icon |
| Label shows "…" though `numberOfLines == 0` | stale wrap height after container width settled smaller | self-syncing `preferredMaxLayoutWidth` label |
