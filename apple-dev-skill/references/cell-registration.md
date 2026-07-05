# Cell Registration

## Core Principle

**For `UICollectionView`, prefer `UICollectionView.CellRegistration` (iOS 14+) over legacy string-based `register` + `dequeueReusableCell`.**

Compile-time type safety, no reuse-identifier typos, configuration centralized in one handler closure.

**`UITableView` has no `CellRegistration` API** — UIKit never shipped one. For table views, use legacy `register(_:forCellReuseIdentifier:)` + `dequeueReusableCell`, optionally wrapped in a generic helper for type safety:

```swift
extension UITableView {
    func register<T: UITableViewCell>(_ type: T.Type) {
        register(type, forCellReuseIdentifier: String(describing: type))
    }

    func dequeueReusableCell<T: UITableViewCell>() -> T {
        dequeueReusableCell(withIdentifier: String(describing: T.self)) as! T
    }
}
```

## Pitfalls

### 1. Never Create Registration Inside Cell Provider

iOS 15+ crashes if `CellRegistration` is created inside `cellForItemAt` or diffable data source `cellProvider` — even if lazy and only created once.

```swift
// ❌ CRASH on iOS 15+
dataSource = .init(collectionView: cv) { cv, indexPath, item in
    let reg = UICollectionView.CellRegistration<MyCell, MyItem> { cell, _, item in
        cell.configure(with: item)
    }
    return cv.dequeueConfiguredReusableCell(using: reg, for: indexPath, item: item)
}

// ✅ Store as property — create before dequeue
private let cellRegistration = UICollectionView.CellRegistration<MyCell, MyItem> { cell, _, item in
    cell.configure(with: item)
}
```

### 2. One Registration per Content Configuration Type

Mixing different `UIContentConfiguration` types on the same registration triggers UIKit warning and expensive content view replacement. Each registration manages its own reuse pool — different configuration types need different registrations.

### 3. Closure Capture — Watch for Retain Cycles

Registration is a stored property → handler captures `self` → retain cycle: `VC → registration → handler → VC`.

**Preferred**: handler uses only `(cell, indexPath, item)` parameters, no external capture. When external references are needed, use `[weak self]`.

### 4. Dynamic / Server-Driven Cell Types — Fall Back to Legacy

CellRegistration requires all registrations to exist before dequeue. For truly dynamic cell types unknown at startup (unbounded server-driven set), **use legacy `register` + `dequeueReusableCell`**.

Registration objects are lightweight — pre-creating many is fine. Only fall back when the type set is genuinely unbounded at compile time.

## Handler Lifecycle

The handler runs on every `dequeueConfiguredReusableCell` call, **after** `prepareForReuse()`. Always build configuration from scratch (`defaultContentConfiguration()`), set all fields, assign to `cell.contentConfiguration`. Do not read-modify-write existing configuration.

## Integration with List Composition

When using the [list-composition](list-composition.md) row/item controller pattern, each row controller owns its own registration:

```swift
final class AvatarItemController: ItemControllerDataSource {
    private let model: AvatarViewModel

    private let registration = UICollectionView.CellRegistration<AvatarCell, AvatarViewModel> { cell, _, model in
        cell.configure(with: model)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: model)
    }
}
```

Cell type knowledge stays inside the row controller. No shared string identifiers to coordinate.
