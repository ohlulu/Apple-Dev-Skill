# Compound Cell Row Animation

Animating row insert/remove inside a compound collection view cell (one cell containing a vertical UIStackView of multiple row views). Applies to settings-style screens where each section is a single cell with stacked rows.

## The Problem

A compound cell's `configure(with: [UIView])` teardowns and rebuilds its entire stack. When a row needs to appear/disappear with animation (e.g. an "Auto Lock After" row conditional on a switch toggle), three naïve approaches all fail:

| Approach | Failure mode |
|----------|-------------|
| `reconfigureItems` + `animatingDifferences: true` | All cell content is rebuilt inside `UIView.animate` — UISwitch and other complex controls distort (see below) |
| `reconfigureItems` + `animatingDifferences: false` | Cell content updates instantly — no animation for the row appearance |
| Direct cell rebuild + `UIView.animate { invalidateLayout(); layoutIfNeeded() }` | New views start at (0,0) and animate to final position — content jumps |

## UISwitch Distortion Trap

**When UISwitch (or any UIKit control with complex internal subview hierarchy) is created inside a `UIView.animate` block, its internal subviews interpolate from zero frame to final frame.** `cornerRadius` is a `CALayer` property that does not participate in `UIView` property animation. The result: the switch appears as a rectangle during the transition.

This happens when:
- `diffableDataSource.apply(snapshot, animatingDifferences: true)` with `reconfigureItems` — the data source wraps `cellProvider` inside an animation context
- `performBatchUpdates` wraps cell reconfiguration
- Any `UIView.animate` block that triggers cell content rebuild via `configure(with:)`

**Rule: never create UISwitch, UISegmentedControl, or similar complex controls inside an animation block.** If you need to animate a cell that contains these controls, animate around them — don't rebuild the cell.

## Correct Pattern: UIStackView `isHidden` + `performBatchUpdates`

Instead of rebuilding the cell, manipulate existing arranged subviews:

### Cell API

Add row-level insert/remove methods to the compound cell:

```swift
final class CompoundCardCell: UICollectionViewCell {
    private let stackView: UIStackView = { ... }()

    /// Full rebuild — use for initial configuration only.
    func configure(with rows: [UIView]) { ... }

    /// Append a row with separator, initially hidden.
    /// Call inside `performBatchUpdates` with `revealLastRow()`.
    func appendRowHidden(_ row: UIView) {
        let sep = SeparatorView()
        sep.isHidden = true
        sep.alpha = 0
        row.isHidden = true
        row.alpha = 0
        stackView.addArrangedSubview(sep)
        stackView.addArrangedSubview(row)
    }

    /// Reveal the last row + separator.
    /// Call inside `performBatchUpdates` block.
    func revealLastRow() {
        guard stackView.arrangedSubviews.count >= 2 else { return }
        let row = stackView.arrangedSubviews[stackView.arrangedSubviews.count - 1]
        let sep = stackView.arrangedSubviews[stackView.arrangedSubviews.count - 2]
        row.isHidden = false
        row.alpha = 1
        sep.isHidden = false
        sep.alpha = 1
    }

    /// Hide the last row + separator for animated collapse.
    /// Call inside `performBatchUpdates` block.
    /// Follow with `removeHiddenRows()` in completion.
    func hideLastRow() {
        guard stackView.arrangedSubviews.count >= 2 else { return }
        let row = stackView.arrangedSubviews[stackView.arrangedSubviews.count - 1]
        let sep = stackView.arrangedSubviews[stackView.arrangedSubviews.count - 2]
        row.isHidden = true
        row.alpha = 0
        sep.isHidden = true
        sep.alpha = 0
    }

    /// Remove hidden views from hierarchy. Call after animation completes.
    func removeHiddenRows() {
        for view in stackView.arrangedSubviews where view.isHidden {
            view.removeFromSuperview()
        }
    }
}
```

### Call Site

```swift
func toggleConditionalRow() {
    guard let indexPath = dataSource.indexPath(for: .privacyGroup),
          let cell = collectionView.cellForItem(at: indexPath) as? CompoundCardCell else {
        // Cell not visible — snapshot rebuild is safe
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.privacyGroup])
        dataSource.apply(snapshot, animatingDifferences: false)
        return
    }

    if shouldShowRow {
        cell.appendRowHidden(makeConditionalRow())
        collectionView.performBatchUpdates {
            cell.revealLastRow()
        }
    } else {
        collectionView.performBatchUpdates {
            cell.hideLastRow()
        } completion: { _ in
            cell.removeHiddenRows()
        }
    }
}
```

### Why This Works

1. **UISwitch stays untouched** — it was created during initial `configure(with:)`, outside any animation block. Its frame never changes.
2. **UIStackView animates `isHidden`** — Apple intercepts `isHidden` changes on arranged subviews and converts them to height animations automatically. Safe here because *you* drive the toggle and re-drive it on the next one; a diffable data source flipping the same flag from inside an animated `apply` can strand the transition permanently — see [diffable-data-source](diffable-data-source.md) → "Downstream Trap: reconfigure inside an animated apply".
3. **`performBatchUpdates`** — tells the collection view to re-query `preferredLayoutAttributesFitting` for affected cells. The cell reports its new intrinsic height, and the collection view animates all cells below to their new positions.

### Why `invalidateLayout()` Fails Here

`UICollectionViewCompositionalLayout` caches cell sizes after the initial `preferredLayoutAttributesFitting` call. `invalidateLayout()` invalidates positions but does **not** force re-measurement of cell sizes. The cell content changes but surrounding cells don't move — they overlap.

`performBatchUpdates` is the correct mechanism to trigger re-measurement in compositional layout. It processes the batch as an animated layout update, re-querying cell sizes and animating position changes.

| Method | Re-measures cell sizes? | Animates? |
|--------|------------------------|-----------|
| `invalidateLayout()` | ❌ (uses cached) | No |
| `invalidateLayout()` + `layoutIfNeeded()` inside `UIView.animate` | ❌ | Animates positions only |
| `performBatchUpdates(nil)` | ✅ | ✅ |
| `reconfigureItems` + `apply(animatingDifferences: true)` | ✅ | ✅ (but rebuilds cell — control distortion) |

### Coordinating with UISwitch Toggle

When a UISwitch controls the conditional row's visibility, the switch has its own 0.3s animation. Don't interrupt it:

```swift
switchToggleHandler = { [weak self] isOn in
    Task { @MainActor in
        guard let self else { return }
        let accepted = await viewModel.setEnabled(isOn)
        if !accepted {
            // Revert immediately
            self.toggleConditionalRow()
        } else {
            // Wait for switch animation to finish
            try? await Task.sleep(for: .seconds(0.3))
            self.toggleConditionalRow()
        }
    }
}
```

**Important**: the viewModel's state-change method should NOT call `onDataChanged` (which triggers full `applySnapshot` → cell rebuild). The toggle handler manages UI updates directly with proper timing.
