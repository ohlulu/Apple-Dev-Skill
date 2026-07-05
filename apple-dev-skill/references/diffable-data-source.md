# Diffable Data Source

## Default Choice

**For any new list / collection, diffable is the default. Reach for manual `UITableViewDataSource` / `UICollectionViewDataSource` only with a documented reason** (Swift 6 friction that can't be resolved with the patterns below, an `iOS < 13` deployment target, or a measured perf gate that diffable can't hit).

Manual data sources reliably accumulate three latent costs that diffable removes:

1. **Selection-only refresh defaults to `reloadData()`**. Engineers conflate "highlight the new row" with "refresh the table" and call `reloadData()`. Visible cells re-dequeue, the `automaticDimension` height cache is invalidated, sticky headers re-attach — a one-frame visible flicker on every tap. Diffable's `reconfigureItems([oldId, newId])` makes the cheap path the natural path.
2. **Insert / delete needs manual `performBatchUpdates`** plus a parallel data-structure diff. Most apps skip this and call `reloadData()` again, losing free animations and re-introducing the flicker above.
3. **Stale-callback safety is hand-rolled** (`guard indexPath.section < sections.count && indexPath.row < ...`). Diffable handles this natively via `itemIdentifier(for:)` returning nil.

When reviewing a PR or inheriting code with a manual data source, the question to ask is "why isn't this diffable?" — not "should we add diffable?"

## Core Principle

Both type parameters of `UICollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>` and `UITableViewDiffableDataSource` **require only `Hashable`, not `Identifiable`**.

Diffable's responsibility split:

- **Identity changes** (which rows exist, in what order) → handled **automatically** via snapshot diff (insert / delete / move / reorder)
- **Content changes within the same row** (same id, different fields) → **must** be triggered explicitly with `reconfigureItems(_:)`

These are two deliberately separated responsibilities — not a hole in the automatic diff.

## ItemIdentifierType: Two Apple-Blessed Patterns

Apple has endorsed both patterns since WWDC 2019. Choose based on whether the model crosses into other frameworks (SwiftUI / Combine).

### Pattern A: the whole model as identifier

The WWDC 2019 Session 220 demo shape — the model struct itself is `Hashable` and used directly as the identifier.

```swift
struct Product: Hashable {
    let id: String
    var name: String
    var stock: Int
    // Synthesized Hashable: all properties participate
}

private var dataSource: UICollectionViewDiffableDataSource<Section, Product>!

dataSource = .init(collectionView: cv) { cv, indexPath, product in
    cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: product)
}
```

**Content-change behavior** (with the synthesized hash):

- `stock` changes → hash changes → diffable treats it as **delete old + insert new** → cell is re-dequeued → visible flicker
- Fix: call `reconfigureItems([newProduct])` explicitly to keep the existing cell

**Variant**: custom `Hashable` comparing only `id` (so diffable treats a stock change as "same item"):

```swift
extension Product {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Product, r: Product) -> Bool { l.id == r.id }
}
// stock changes → hash unchanged → diffable sees "identical, do nothing"
// You MUST call reconfigureItems to tell it "content changed"
```

Legal but with a side effect: once this `Hashable` crosses into SwiftUI (`ForEach`, `.animation(_:value:)`, `.equatable()`) or Combine equality streams, they will wrongly conclude "content didn't change."

### Pattern B: ID as identifier, cellProvider looks up the model

```swift
struct Product: Hashable {                          // synthesized is fine; content changes stay detectable
    let id: String
    var name: String
    var stock: Int
}

private var dataSource: UICollectionViewDiffableDataSource<Section, String>!
private var products: [String: Product] = [:]      // ID → model lookup

dataSource = .init(collectionView: cv) { [weak self] cv, indexPath, id in
    guard let product = self?.products[id] else { return nil }
    return cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: product)
}

func updateStock(productID: String, newStock: Int) {
    products[productID]?.stock = newStock           // update the source of truth
    var snapshot = dataSource.snapshot()
    snapshot.reconfigureItems([productID])          // tell diffable "same id, new content"
    dataSource.apply(snapshot, animatingDifferences: false)
}
```

The ItemIdentifierType is `String` — diffable physically cannot see `stock`. "Automatic content-change detection" is impossible by construction, which is exactly why `reconfigureItems` exists.

### Choosing between the patterns

| Situation | Pick |
|-----------|------|
| Model serves only UIKit diffable, never crosses frameworks | A (simplest syntax) |
| Model is also consumed by SwiftUI `ForEach` / Combine `Equatable` | B (identity and content separated at the type level) |
| Server frequently pushes the same id with different fields | B (update is just `products[id] = new` + reconfigure) |
| The cell's display data IS the model, and the model is a stable value type | A |

**Mental model**: Pattern A collapses identity and content onto one `Hashable`; Pattern B separates them at the type level. Which is simpler and which is safer depends on where the model flows.

## reconfigureItems vs reloadItems vs apply

Three update APIs on iOS 15+, each with a distinct job:

| API | Behavior | Use for |
|-----|----------|---------|
| `apply(snapshot, animatingDifferences:)` | Diffs old vs new identifier sequences; computes insert/delete/move | Structural changes |
| `reconfigureItems([id])` + apply | Reuses the existing cell; re-runs cellProvider | Same row, content changed (**preferred**) |
| `reloadItems([id])` + apply | Dequeues a brand-new cell; re-runs cellProvider | Changing the cell type, or full rebuild needed |
| `applySnapshotUsingReloadData(_:)` | Equivalent to legacy `reloadData()`; drops all cached cells | Replacing the whole data set |

Apple's documentation on `reconfigureItems`: "choose to reconfigure items instead of reloading items unless you have an explicit need to replace the existing cell with a new cell."

Apple UIKit engineer Tyler Fox:

> Reload: replaces the existing cell with a new cell.
> Reconfigure: allows you to directly update the existing cell.
> Reconfigure preserves existing prepared cells — cached cells which were either prefetched, or already displayed and are waiting to become visible again.

### How reconfigureItems behaves internally

For each id:

1. If no cell for that id exists in the collection view's prepared-cell cache → no-op
2. If one exists → cellProvider is called, but `dequeueConfiguredReusableCell` returns **the same existing cell** instance (no new dequeue)
3. The cellProvider must dequeue the same cell type (same registration / reuse identifier)

**Precondition**: the cell type doesn't change. To swap cell types, use `reloadItems`.

### Downstream Trap: iPadOS Cell Focus Halo

`reloadData()` / `reloadItems` re-dequeue cells, which has a load-bearing side effect on iPad: **the system clears any active focus association on the dequeued cell**. iPadOS draws a default focus halo (`UICell.FocusEffect.automatic`, ~3pt accent-tinted ring outside the cell bounds) on the most recently tapped cell when:

- The cell is selectable (`allowsSelection != .none`)
- The cell hosts a tap-driven action (e.g. `didSelectRowAt`)
- `focusEffect` is not explicitly set to `nil`

Migrating from `reloadData()` → `reconfigureItems` (or `reconfigureRows(at:)` on classic table views) keeps the cell instance attached, so the focus halo persists on top of any selection styling the cell renders itself. Symptom: "after I switched to reconfigure, the tapped row has a thick bright accent ring that looks nothing like my configured 1pt border."

```swift
// In the cell init — disable the system halo when the cell renders
// its own selection appearance (border + tinted bg, etc.)
override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    focusEffect = nil          // iOS 15+; suppresses the iPadOS halo
    setupUI()
}
```

Keep the default halo only when the list is intentionally focus-driven (external keyboard / trackpad navigation, accessibility focus rings). For a touch-only data-entry app, the halo is redundant chrome the moment the cell has its own `isSelected` visual.

**The trap is bi-directional**: any time you replace `reloadData()` / `reloadItems` with `reconfigureItems` (or the non-diffable `reconfigureRows(at:)`), audit the cell for a custom selection appearance. The old reload path was suppressing the halo as a side effect; the new path no longer does.

## iOS 15 Behavior Change

The semantics of `apply(_:animatingDifferences:)` changed in iOS 15:

| Call | iOS 14 and earlier | iOS 15+ |
|------|--------------------|---------|
| `apply(snapshot, animatingDifferences: true)` | diff + animate | diff + animate |
| `apply(snapshot, animatingDifferences: false)` | **equivalent to `reloadData`** (drops all cells) | **diff without animation** (lightweight) |
| To actually reloadData | the row above | **new API** `applySnapshotUsingReloadData(_:)` |

Hidden risk after raising the deployment target past iOS 15: old code that used `animatingDifferences: false` as a "force full reload" hack now performs a diff instead — which can expose cell-reuse bugs the old `reloadData` was masking.

Backward-compatible helper:

```swift
extension UICollectionViewDiffableDataSource {
    func applySnapshot(_ snapshot: Snapshot, animated: Bool) {
        if #available(iOS 15.0, *) {
            apply(snapshot, animatingDifferences: animated)
        } else if animated {
            apply(snapshot, animatingDifferences: true)
        } else {
            UIView.performWithoutAnimation {
                apply(snapshot, animatingDifferences: true)
            }
        }
    }
}
```

## Background Thread Safety

Snapshots are value types (structs) and can be assembled off the main thread:

```swift
Task.detached {
    var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
    snapshot.appendSections([.main])
    snapshot.appendItems(heavyComputedIDs)
    await dataSource.apply(snapshot, animatingDifferences: true)
}
```

**But don't mix**: never drive the same dataSource sometimes from the main thread and sometimes from the background. Pin one thread (usually all-main) or serialize everything through an actor.

## Identifiable Has Nothing to Do with Diffable

`UICollectionViewDiffableDataSource<S, I>` constrains `I` to `Hashable`. `Identifiable` is not required.

`Identifiable` is SwiftUI vocabulary (`ForEach` reads `\.id` automatically). If one model struct serves both UIKit diffable and SwiftUI, conform separately, or use `ForEach(items, id: \.id)` to avoid forcing `Identifiable` onto the model.

## Common Mistakes

| Pattern | Symptom | Fix |
|---------|---------|-----|
| Whole mutable model as ItemIdentifierType (synthesized Hashable), then plain `apply` on content change | Row delete + insert → flicker | Use `reconfigureItems([newItem])` to keep the cell, or switch to Pattern B |
| Custom `Hashable` comparing only id, model also fed to SwiftUI `ForEach` / `.animation(_:value:)` | SwiftUI can't see content changes, UI doesn't update | Separate identity from content: Pattern B, or a dedicated `Equatable` view-model for SwiftUI |
| Using `animatingDifferences: false` expecting a full reload | On iOS 15+ it's a lightweight diff; bugs previously masked by reloadData surface | Use `applySnapshotUsingReloadData` when a real reload is intended |
| Creating `CellRegistration` inside the cellProvider | Crash on iOS 15+ | Hoist the registration to a stored property — see [cell-registration](cell-registration.md) |
| Driving the same dataSource from multiple threads | Data races / animation glitches | Pin to the main thread, or serialize through an actor |
| Dequeuing a different cell type during reconfigure | UIKit assertion | Changing cell type requires `reloadItems`, not `reconfigureItems` |
| Porting a reloadData()-based shell to diffable where `display(_:)` only calls `apply(snapshot)` | Rows whose id is unchanged but content changed (cart quantity, subtotal, row-internal view model) go silently stale — the diff can't see the change | Add `snapshot.reconfigureItems(snapshot.itemIdentifiers)` before `apply`, preserving the old "refresh everything on display" contract |
| `reconfigureItems([id])` on a selection / setSelected path without filtering ids missing from the snapshot | iOS warning / `NSInternalInconsistencyException` | Before apply: `let known = Set(snap.itemIdentifiers); snap.reconfigureItems(ids.filter { known.contains($0) })` |

## When to Reach for Diffable

| Scenario | Use diffable? |
|----------|---------------|
| Multiple sections, heterogeneous cells, frequent inserts/deletes | ✅ |
| Server-push updates that should animate | ✅ |
| Snapshot assembly on a background thread | ✅ |
| Purely static list that never changes | Diffable is fine, but the payoff is small |
| Extreme scroll performance, tens of thousands of cells | Manage the data source manually under `UICollectionViewCompositionalLayout`; diffable's apply still pays a diff cost on very large data sets |

## References

- WWDC 2019 Session 220 "Advances in UI Data Sources" — diffable's introduction; the whole-model identifier pattern
- WWDC 2021 Session 10252 "Make Blazing Fast Lists and Collection Views" — `reconfigureItems`, iOS 15 behavior change
- Apple Developer Forums #126742 — Apple engineers on the legitimacy of "whole model as identifier"
- Apple docs: [reconfigureItems](https://developer.apple.com/documentation/uikit/nsdiffabledatasourcesnapshot/3804468-reconfigureitems), [applySnapshotUsingReloadData](https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource/3804470-applysnapshotusingreloaddata)

Related references in this skill:

- [cell-registration](cell-registration.md) — CellRegistration pairing rules; registrations must not live inside the cellProvider
- [list-composition](list-composition.md) — where diffable sits in the row/item controller architecture
