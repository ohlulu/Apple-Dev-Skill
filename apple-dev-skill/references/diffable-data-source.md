# Diffable Data Source

## Default Choice

**For any new list / collection, diffable is the default. Reach for manual `UITableViewDataSource` / `UICollectionViewDataSource` only with a documented reason** (Swift 6 friction that can't be resolved with the patterns below, an `iOS < 13` deployment target, or a measured perf gate that diffable can't hit).

Manual data sources reliably accumulate three latent costs that diffable removes:

1. **Selection-only refresh defaults to `reloadData()`**. Engineers conflate "highlight the new row" with "refresh the table" and call `reloadData()`. Visible cells re-dequeue, `automaticDimension` height cache is invalidated, sticky headers re-attach — a one-frame visible flicker on every tap. Diffable's `reconfigureItems([oldId, newId])` makes the cheap path the natural path.
2. **Insert / delete needs manual `performBatchUpdates`** and a parallel data-structure diff. Most apps skip this and call `reloadData()` again, losing free animations and re-introducing the flicker above.
3. **Stale-callback safety is hand-rolled** (`guard indexPath.section < sections.count && indexPath.row < ...`). Diffable handles this natively via `itemIdentifier(for:)` returning nil.

When reviewing a PR or inheriting code with a manual data source, the question to ask is "why isn't this diffable?" — not "should we add diffable?"

## Core Principle

`UICollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>` 與 `UITableViewDiffableDataSource` 的兩個 type parameter **只要求 `Hashable`，不要求 `Identifiable`**。

Diffable 的職責切割：
- **identity 變動**（哪些 row 在、怎麼排）→ Diffable 透過 snapshot diff **自動處理**（insert / delete / move / reorder）
- **同一 row 的內容變動**（id 不變、欄位變）→ **必須**用 `reconfigureItems(_:)` 顯式觸發

兩者是設計上分開的責任，不是「自動 diff 有漏洞」。

## ItemIdentifierType: Two Apple-Blessed Patterns

Apple 從 WWDC 2019 起同時祝福兩種寫法。選擇依「model 是否跨到其他框架（SwiftUI / Combine）」而定。

### Pattern A：整個 model 當 identifier

WWDC 2019 Session 220 主示範。Mountain struct 本身 `Hashable`，直接當 identifier 使用。

```swift
struct Product: Hashable {
    let id: String
    var name: String
    var stock: Int
    // Synthesized Hashable: 所有屬性參與
}

private var dataSource: UICollectionViewDiffableDataSource<Section, Product>!

dataSource = .init(collectionView: cv) { cv, indexPath, product in
    cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: product)
}
```

**內容變動行為**（用 synthesized hash）：
- stock 變 → hash 變 → Diffable 視為 **delete 舊 + insert 新** → cell dequeue 重建 → 閃爍
- 解法：明確呼叫 `reconfigureItems([newProduct])` 保留現有 cell

**變體**：自訂 `Hashable` 只比 id（讓 Diffable 視 stock 變動為「同一筆」）：
```swift
extension Product {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Product, r: Product) -> Bool { l.id == r.id }
}
// stock 變 → hash 不變 → Diffable 視為「完全相同、不動作」
// 必須明確 reconfigureItems 告訴它「內容變了」
```
合法但有副作用：此 `Hashable` 一旦跨到 SwiftUI（`ForEach`、`.animation(_:value:)`、`.equatable()`）或 Combine 比較流會誤判「內容沒變」。

### Pattern B：ID 當 identifier、cellProvider 查 model

```swift
struct Product: Hashable {                          // synthesized 即可,內容變可偵測
    let id: String
    var name: String
    var stock: Int
}

private var dataSource: UICollectionViewDiffableDataSource<Section, String>!
private var products: [String: Product] = [:]      // ID 查 model

dataSource = .init(collectionView: cv) { [weak self] cv, indexPath, id in
    guard let product = self?.products[id] else { return nil }
    return cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: product)
}

func updateStock(productID: String, newStock: Int) {
    products[productID]?.stock = newStock           // 更新真相
    var snapshot = dataSource.snapshot()
    snapshot.reconfigureItems([productID])          // 告訴 Diffable「同 id、內容變」
    dataSource.apply(snapshot, animatingDifferences: false)
}
```

ItemIdentifierType 是 `String`，Diffable 物理上看不到 stock。「自動偵測內容變化」對它而言不可能——這正是 `reconfigureItems` 存在的理由。

### Pattern 選擇判準

| 情境 | 選 |
|------|----|
| Model 只服務 UIKit Diffable、不跨框架 | A（語法最簡） |
| Model 同時被 SwiftUI `ForEach` / Combine `Equatable` 使用 | B（identity 與 content 在型別層級分開） |
| Server payload 頻繁推同 id 不同欄位 | B（更新只需 `products[id] = new` + reconfigure） |
| Cell 顯示需要的資訊就是 model 本身、且 model 是穩定 value type | A |

**心法**：A pattern 把 identity 與 content 都壓在同一個 `Hashable` 上；B pattern 在型別層級把兩者分開。哪個簡單、哪個安全，看 model 流向哪裡。

## reconfigureItems vs reloadItems vs apply

iOS 15+ 三種更新 API，各有用途：

| API | 行為 | 用途 |
|-----|------|------|
| `apply(snapshot, animatingDifferences:)` | 比較新舊 snapshot 的 identifier 序列、自動算 insert/delete/move | 結構性變動 |
| `reconfigureItems([id])` + apply | 重用現有 cell、重跑 cellProvider | 同一 row、內容變動（**首選**） |
| `reloadItems([id])` + apply | dequeue 全新 cell、重跑 cellProvider | 需要更換 cell type、或需要徹底重建 |
| `applySnapshotUsingReloadData(_:)` | 等同舊版 `reloadData()`、丟掉所有快取 cell | 整批換成完全不同的資料 |

Apple 官方文件對 `reconfigureItems` 的建議：「choose to reconfigure items instead of reloading items unless you have an explicit need to replace the existing cell with a new cell.」

Apple UIKit team 的 Tyler Fox：
> Reload: replaces the existing cell with a new cell.
> Reconfigure: allows you to directly update the existing cell.
> Reconfigure preserves existing prepared cells — cached cells which were either prefetched, or already displayed and are waiting to become visible again.

### reconfigureItems 內部行為

對每筆 id：
1. 若該 id 對應的 cell 不存在於 collection view 的 prepared cell cache → no-op
2. 若存在 → 呼叫 cellProvider，但 `dequeueConfiguredReusableCell` 會回傳**同一個現有的 cell** instance（不 dequeue 新的）
3. 你必須在 cellProvider 內 dequeue 同一個 cell type（相同 registration / reuse identifier）

**前提**：cell type 不變。需要換 cell type 時改用 `reloadItems`。

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

Keep the default halo only when the list is intentionally focus-driven (external keyboard / trackpad navigation, accessibility focus rings). For a touch-only POS / data-entry app, the halo is redundant chrome the moment the cell has its own `isSelected` visual.

**The trap is bi-directional**: any time you replace `reloadData()` / `reloadItems` with `reconfigureItems` (or the non-diffable `reconfigureRows(at:)`), audit the cell for a custom selection appearance. The old reload path was suppressing the halo as a side effect; the new path no longer does.

## iOS 15 Behavior Change（常考點）

`apply(_:animatingDifferences:)` 的語意在 iOS 15 變了：

| 呼叫 | iOS 14 及以前 | iOS 15+ |
|------|--------------|---------|
| `apply(snapshot, animatingDifferences: true)` | diff + 動畫 | diff + 動畫 |
| `apply(snapshot, animatingDifferences: false)` | **等同 `reloadData`**（丟所有 cell） | **diff + 無動畫**（輕量） |
| 要真正 reloadData | 用上面那行 | **新 API** `applySnapshotUsingReloadData(_:)` |

升 iOS 15 後的隱性風險：舊 code 用 `animatingDifferences: false` 當「強制全 reload」的 hack，現在會改成 diff——可能曝出原本被 `reloadData` 掩蓋的 cell 重用 bug。

向下相容的 helper：

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

Snapshot 是 value type（struct），可在 background 組裝：

```swift
Task.detached {
    var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
    snapshot.appendSections([.main])
    snapshot.appendItems(heavyComputedIDs)
    await dataSource.apply(snapshot, animatingDifferences: true)
}
```

**但不要混用**：同一個 dataSource 不要時而主緒、時而背景操作。固定一條 thread（最常見是全主緒），或全程透過 actor 序列化。

## Identifiable 與 Diffable 沒有關係

`UICollectionViewDiffableDataSource<S, I>` 對 `I` 的約束是 `Hashable`。不需要 `Identifiable`。

`Identifiable` 是 SwiftUI 用語（`ForEach` 自動讀 `\.id`）。如果同一個 model struct 同時被 UIKit Diffable 與 SwiftUI 使用，可以分開掛 conformance、或用 `ForEach(items, id: \.id)` 避免讓 model 強制 conform `Identifiable`。

## Common Mistakes

| 寫法 | 症狀 | 修法 |
|------|------|------|
| 把整個 mutable model 當 ItemIdentifierType（synthesized Hashable），內容變動時直接 `apply` | 整 row delete + insert → 閃爍 | 改 `reconfigureItems([newItem])` 保留 cell；或改 Pattern B |
| 自訂 `Hashable` 只比 id，又把同一 model 給 SwiftUI `ForEach` / `.animation(_:value:)` 用 | SwiftUI 看不到內容變化、UI 不更新 | identity 與 content 分開：Pattern B、或為 SwiftUI 另寫 `Equatable` view-model |
| `@State var products: [Product]` 接外部資料 | 父層更新 child 看不到 | 改 `let products` 或 `@Binding` |
| `ForEach(products) { ... }.id(product.id)` | 多餘的 `.id()` 造成 identity churn | 移除 `.id`，靠 `Identifiable` 或 `id: \.id` |
| `ProductRow: Equatable` 但沒掛 `.equatable()` modifier | 自訂 `==` 不生效、SwiftUI 仍每次重算 body | 在使用處掛 `.equatable()` 或用 `EquatableView { ... }` |
| 用 `animatingDifferences: false` 想「徹底 reload」 | iOS 15 起變成輕量 diff，原本被 reloadData 掩蓋的 bug 浮現 | 真要 reload 改 `applySnapshotUsingReloadData` |
| 在 cellProvider 內 `let reg = CellRegistration(...)` | iOS 15+ crash | Registration 提出來當 stored property，見 [cell-registration](cell-registration.md) |
| 跨 thread 混用同一 dataSource | data race / 動畫錯亂 | 固定主緒，或全程 actor 序列化 |
| reconfigure 時改 dequeue 不同的 cell type | UIKit assertion | 換 cell type 必須用 `reloadItems`，不是 `reconfigureItems` |
| 將 reloadData()-based shell 迷入 diffable，`display(_:)` 只呼以 `apply(snapshot)` | id 不變但內容變動的 row（購物車數量、小計、row 內部 view model）静默 stale；diff 看不見變化 | `apply` 前一行 `snapshot.reconfigureItems(snapshot.itemIdentifiers)`，保留與 reloadData() 同謞的 「每次都刷」 contract |
| `reconfigureItems([id])` 在 selection / setSelected 路徑未先濾掉 snapshot 不存在的 id | iOS 警告 / `NSInternalInconsistencyException` | apply 前 `let known = Set(snap.itemIdentifiers); snap.reconfigureItems(ids.filter { known.contains($0) })` |

## When to Reach for Diffable

| 場景 | 用 Diffable？ |
|------|--------------|
| 多 section、heterogeneous cells、頻繁增刪 | ✅ |
| Server push 更新、需要動畫過渡 | ✅ |
| 需要在背景組裝 snapshot | ✅ |
| 純靜態列表、永不變動 | 用 Diffable 也 OK，但收益低 |
| 需要極致 scroll 效能、cell 數萬筆 | 改 `UICollectionViewCompositionalLayout` 自己管 data source；Diffable apply 對極大資料集仍會有 diff 成本 |

## References

- WWDC 2019 Session 220「Advances in UI Data Sources」— Diffable 首次發表，Mountain pattern
- WWDC 2021 Session 10252「Make Blazing Fast Lists and Collection Views」— `reconfigureItems`、iOS 15 行為變更
- Apple Developer Forums #126742 — Apple 工程師討論「whole model as identifier」的合法用法
- Apple docs: [reconfigureItems](https://developer.apple.com/documentation/uikit/nsdiffabledatasourcesnapshot/3804468-reconfigureitems)、[applySnapshotUsingReloadData](https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource/3804470-applysnapshotusingreloaddata)

相關 skill 內條目：
- [cell-registration](cell-registration.md) — CellRegistration 的搭配寫法、registration 不能放 cellProvider 內
- [list-composition](list-composition.md) — row/item controller 架構下 Diffable 的位置
