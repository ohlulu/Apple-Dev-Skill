# List Composition Patterns

## Overview

Use row/item controllers and section controllers only when list complexity earns the extra indirection.

Goal:
- keep the list container thin
- keep row/section behavior local
- tie async work to UIKit lifecycle
- preserve stable identity during diffable updates

For simple lists, prefer direct `UITableViewDiffableDataSource`, `UICollectionViewDiffableDataSource`, `CellRegistration`, or a focused view controller.

## Design Intent

The pattern exists to solve one problem: **a growing `switch indexPath` in a view controller that mixes cell creation, async loading, cancellation, and selection for many different cell types.**

The solution decomposes into three roles:

| Role | Responsibility | Knows about concrete cell types? |
|------|---------------|----------------------------------|
| **Row/Item Controller** | Owns one row's full lifecycle — create, configure, display, prefetch, cancel, select | Yes — exactly one |
| **Wrapper (CellController)** | Type-erases the row controller so heterogeneous controllers can live in one diffable snapshot | No |
| **Container (ListViewController)** | Holds the diffable data source, forwards delegate calls to the correct wrapper | No |

Key architectural properties:
- **Open-Closed**: new cell types = new row controller class; container and wrapper unchanged
- **No base class**: the wrapper is a struct; concrete controllers are independent objects
- **Composition Root assembly**: the place that creates row controllers and wraps them into `CellController` is outside all three roles

Adapt the shapes to the project. The code skeletons below are starting points — not sacred templates. What matters is preserving the three-role separation and the dispatch contract.

## Decision Rule

### Consider row/item controllers when the list has:
- multiple cell types
- row-specific selection behavior
- async image or data loading per row
- prefetching and cancellation
- load-more / pagination rows
- a view controller growing around `switch indexPath.section` or `switch indexPath.row`

### Prefer simpler list code when the list has:
- one cell type
- trivial cell configuration
- no async row work
- little row-specific interaction
- one or two sections with minimal behavior

## Row / Item Controllers

A row/item controller owns:
- cell creation and configuration
- selection handling
- `willDisplay` / `didEndDisplaying`
- prefetch start / cancel
- async request start / cancel
- stable item identity

### Default Row Wrapper (UITableView)

```swift
/// Conform to this to create a row controller wrappable in CellController.
///
/// Only `cellForRowAt` is required. The diffable data source handles
/// `numberOfRowsInSection` — do not implement it in row controllers.
///
/// The container dispatches ONLY these delegate methods to row controllers:
///   UITableViewDelegate:
///     - willDisplay(_:forRowAt:)
///     - didEndDisplaying(_:forRowAt:)
///     - didSelectRowAt(_:)
///   UITableViewDataSourcePrefetching:
///     - prefetchRowsAt(_:)
///     - cancelPrefetchingForRowsAt(_:)
///
/// Any other delegate method is silently ignored. If your row controller
/// needs a method not listed above, add the forwarding to the container
/// first, then update the dispatch manifest.
protocol CellControllerDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
}

struct CellController {
    let id: AnyHashable
    let dataSource: CellControllerDataSource
    let delegate: UITableViewDelegate?
    let prefetching: UITableViewDataSourcePrefetching?

    /// - Parameter dataSource: The row controller. Also checked at init time
    ///   for UITableViewDelegate and UITableViewDataSourcePrefetching via
    ///   runtime casting — only the methods listed in the dispatch manifest
    ///   will actually be forwarded by the container.
    init(id: AnyHashable, _ dataSource: CellControllerDataSource) {
        self.id = id
        self.dataSource = dataSource
        self.delegate = dataSource as? UITableViewDelegate
        self.prefetching = dataSource as? UITableViewDataSourcePrefetching
    }
}

extension CellController: Equatable {
    static func == (lhs: CellController, rhs: CellController) -> Bool {
        lhs.id == rhs.id
    }
}

extension CellController: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

Derive equality and hashing from `id` only. The stored data source and delegate are behavior, not identity.

The `CellControllerDataSource` protocol replaces raw `UITableViewDataSource` conformance. This eliminates the vestigial `numberOfRowsInSection` from every row controller — the diffable data source already manages row counts from the snapshot. If a project prefers the original approach (conforming directly to `UITableViewDataSource`), that works too — just keep `numberOfRowsInSection` returning `1` in every row controller.

### Default Item Wrapper (UICollectionView)

Same principle — extract a protocol for the minimal required method:

```swift
/// UICollectionView counterpart of CellControllerDataSource.
/// Only `cellForItemAt` is required. The diffable data source handles
/// `numberOfItemsInSection`.
protocol ItemControllerDataSource {
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
}

struct CellController {
    let id: AnyHashable
    let dataSource: ItemControllerDataSource
    let delegate: UICollectionViewDelegate?

    init(id: AnyHashable, _ dataSource: ItemControllerDataSource) {
        self.id = id
        self.dataSource = dataSource
        self.delegate = dataSource as? UICollectionViewDelegate
    }
}

extension CellController: Equatable {
    static func == (lhs: CellController, rhs: CellController) -> Bool {
        lhs.id == rhs.id
    }
}

extension CellController: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

### Row Controller Skeleton

```swift
final class AvatarRowController: NSObject, CellControllerDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    private let model: AvatarViewModel
    private weak var cell: AvatarCell?

    init(model: AvatarViewModel) {
        self.model = model
    }

    // No numberOfRowsInSection — the diffable data source handles it.

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: AvatarCell = tableView.dequeueReusableCell()
        self.cell = cell
        cell.nameLabel.text = model.name
        return cell
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cancelWork()
        self.cell = nil
    }
}
```

Hard rules:
- one row controller per logical row type
- one `CellController` = one row/item — this is enforced by the diffable data source snapshot, not by `numberOfRowsInSection` in the row controller
- store the model the row needs
- release stale cell references on reuse / end-display
- guard duplicate async starts in the controller or loader
- never assume which section or index the controller lives in — the container handles routing
- only rely on delegate methods the container explicitly forwards (see Dispatch Contract below)

## Section Controllers

Section abstractions are optional. Add them only when a section owns real behavior beyond grouping rows/items.

### UITableView Sections

Generate a section controller only when the section owns:
- header or footer view behavior
- header or footer sizing rules
- distinct row composition with clear semantic meaning

Keep the API narrow. Do not expose the full `UITableViewDelegate` surface unless the project already uses that pattern consistently.

#### Section-Level Delegate Dispatch

Section-level delegate methods (header/footer) and cell-level delegate methods (selection, swipe, display) belong to different dispatch targets:

```swift
protocol SectionControllerDataSource {
    func cellControllers() -> [CellController]
}

struct SectionController {
    let dataSource: SectionControllerDataSource
    let sectionDelegate: UITableViewDelegate?

    init(dataSource: SectionControllerDataSource) {
        self.dataSource = dataSource
        self.sectionDelegate = dataSource as? UITableViewDelegate
    }
}
```

The container forwards at two levels:

```swift
// SECTION-LEVEL DISPATCH — header/footer → SectionController.sectionDelegate
override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    sectionController(at: section).sectionDelegate?.tableView?(tableView, viewForHeaderInSection: section)
}

override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    sectionController(at: section).sectionDelegate?.tableView?(tableView, heightForHeaderInSection: section)
        ?? .leastNonzeroMagnitude
}

// CELL-LEVEL DISPATCH — selection/swipe/display → CellController.delegate
override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    cellController(at: indexPath)?.delegate?.tableView?(tableView, didSelectRowAt: indexPath)
}
```

Rules:
- section-level methods go to `SectionController.sectionDelegate`, not to individual cell controllers
- cell-level methods go to `CellController.delegate`
- maintain separate dispatch manifests for each level
- a section controller that only groups cells (no header/footer behavior) does not need `UITableViewDelegate` conformance

### UICollectionView + Compositional Layout

Section controllers are more justified here. A collection section may own:
- item controllers for that section
- supplementary view creation
- `NSCollectionLayoutSection` creation

#### Default Section Wrapper

```swift
protocol SectionControlling {
    var cells: [CellController] { get }
    func layoutSection(at section: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
    func supplementaryView(for collectionView: UICollectionView, kind: String, at indexPath: IndexPath) -> UICollectionReusableView?
}

struct SectionController: Hashable {
    let id: AnyHashable
    let dataSource: SectionControlling
}
```

Generate this by default for compositional layout when sections differ meaningfully in layout, supplementary views, or item composition.

### Stateful Section Controllers

A section controller may own UI state that affects which cells are shown. This is one of the strongest justifications for the section controller abstraction.

Example: an expand/collapse section that controls cell visibility:

```swift
final class PinnedSectionController: SectionControlling {
    private(set) var isExpanded = true
    private let allCells: [CellController]

    var cells: [CellController] {
        isExpanded ? allCells : []
    }

    func toggle() {
        isExpanded.toggle()
    }

    // layoutSection, supplementaryView ...
}
```

When the section is collapsed, it returns an empty array. The diffable snapshot reflects this — the section exists (header/supplementary visible) but contains zero items.

Other cases where section state is justified:
- sections that show a subset of items based on a filter
- sections that conditionally include a "show all" item
- sticky headers that need to track scroll position and update appearance

If a section controller holds no state and its `cellControllers()` is a pure pass-through, it probably doesn't need to be a full class — a struct or even inline construction is enough.

## Containers

The container owns:
- the table/collection view
- diffable data source and snapshots
- screen-level refresh / loading / error UI
- callback forwarding to row/section objects

Keep the container as a forwarding shell. Do not rebuild row behavior inside a large `switch indexPath`.

### UITableView Container Skeleton

```swift
final class ListViewController: UITableViewController, UITableViewDataSourcePrefetching {
    private lazy var dataSource = UITableViewDiffableDataSource<Int, CellController>(tableView: tableView) {
        // DISPATCH MANIFEST — only these methods reach row controllers:
        // UITableViewDelegate:  willDisplay, didEndDisplaying, didSelectRowAt
        // Prefetching:          prefetchRowsAt, cancelPrefetchingForRowsAt
        tableView, indexPath, controller in
        controller.dataSource.tableView(tableView, cellForRowAt: indexPath)
    }

    func display(_ sections: [CellController]...) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, CellController>()
        sections.enumerated().forEach { section, cells in
            snapshot.appendSections([section])
            snapshot.appendItems(cells, toSection: section)
        }
        dataSource.apply(snapshot)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        cellController(at: indexPath)?.delegate?.tableView?(tableView, didSelectRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cellController(at: indexPath)?.delegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cellController(at: indexPath)?.delegate?.tableView?(tableView, didEndDisplaying: cell, forRowAt: indexPath)
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        indexPaths.forEach { indexPath in
            cellController(at: indexPath)?.prefetching?.tableView(tableView, prefetchRowsAt: [indexPath])
        }
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        indexPaths.forEach { indexPath in
            cellController(at: indexPath)?.prefetching?.tableView?(tableView, cancelPrefetchingForRowsAt: [indexPath])
        }
    }

    private func cellController(at indexPath: IndexPath) -> CellController? {
        dataSource.itemIdentifier(for: indexPath)
    }
}
```

Assign `tableView.dataSource = dataSource` and `tableView.prefetchDataSource = self` when configuring the table view.

### Dispatch Contract

The container is a **forwarding shell**. It only dispatches a fixed set of delegate/prefetch methods to row controllers. Any delegate method a row controller implements but the container does not forward is **silently ignored** — no compile-time error, no runtime warning.

When creating or modifying a container, maintain an explicit dispatch manifest. The canonical list of forwarded methods lives in the `CellControllerDataSource` protocol doc comment (see Default Row Wrapper above) — the container's manifest comment should mirror it.

Rules:
- add the manifest as a comment in the container source
- when a row controller needs a delegate method not in the manifest, **add the forwarding to the container first**, then update the manifest
- never assume a row controller's delegate method will be called just because the controller conforms to the protocol
- review the manifest when adding new row controller types — if they need methods not yet forwarded, that is a container change, not a row controller problem

### UICollectionView Container Skeleton

```swift
final class ProductListViewController: UIViewController {
    private lazy var dataSource: UICollectionViewDiffableDataSource<SectionController, CellController> = {
        let ds = UICollectionViewDiffableDataSource<SectionController, CellController>(collectionView: collectionView) {
            collectionView, indexPath, controller in
            controller.dataSource.collectionView(collectionView, cellForItemAt: indexPath)
        }

        // Supplementary views are delegated to the section controller.
        ds.supplementaryViewProvider = { [weak ds] collectionView, kind, indexPath in
            ds?.sectionIdentifier(for: indexPath.section)?
                .dataSource
                .supplementaryView(for: collectionView, kind: kind, at: indexPath)
        }

        return ds
    }()

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            self?.dataSource.sectionIdentifier(for: sectionIndex)?
                .dataSource
                .layoutSection(at: sectionIndex, environment: environment)
        }
    }
}
```

The `supplementaryViewProvider` delegates to the section controller's `supplementaryView(for:kind:at:)`. Each section controller decides what headers, footers, or decorations it needs — the container never switches on section index to pick a supplementary view.

Hard rules:
- keep global layout configuration (e.g. `UICollectionViewCompositionalLayoutConfiguration` with pinned global headers) at the container level
- per-section layout and supplementary views belong to the section controller
- do not move section-specific layout decisions back into a large screen-level switch once section controllers exist

## Incremental Pagination

UIKit code should depend only on:
- current items
- whether more content can be loaded
- a way to request the next page

If the project already has a pagination type, reuse it. When it does not, a minimal seam like this is enough for UIKit list code:

```swift
struct Paginated<Item> {
    let items: [Item]
    let loadMore: (() async throws -> Paginated<Item>)?
}
```

A container can decide whether a load-more row exists from `loadMore != nil` while the actual pagination strategy stays outside UIKit. Map the current page to content `CellController`s, then append an optional load-more `CellController` when another page exists.

### Load-More Row / Item

For visible incremental pagination, a dedicated load-more row/item is often the clearest starting point.

Ownership:
- the container decides whether the load-more row/item exists
- the load-more row/item owns loading UI, error UI, retry UI, and next-page triggering

Trigger priority:
1. use `willDisplay` for simple end-of-list loading
2. add retry interaction for failure states
3. use prefetch or near-end detection only when earlier loading materially improves UX

Consider this shape when the list needs a visible load-more row:

```swift
struct LoadMoreViewModel {
    let isLoading: Bool
    let message: String?

    static let idle = Self(isLoading: false, message: nil)
    static let loading = Self(isLoading: true, message: nil)

    static func error(_ message: String) -> Self {
        Self(isLoading: false, message: message)
    }
}

final class LoadMoreCellController: NSObject, CellControllerDataSource, UITableViewDelegate {
    private let cell = LoadMoreCell()
    private let requestNextPage: () -> Void
    private var isRequestInFlight = false
    private var offsetObserver: NSKeyValueObservation?

    init(requestNextPage: @escaping () -> Void) {
        self.requestNextPage = requestNextPage
    }

    // No numberOfRowsInSection — the diffable data source handles it.

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        reloadIfNeeded()
        offsetObserver = tableView.observe(\.contentOffset, options: [.new]) { [weak self] tableView, _ in
            guard tableView.isDragging else { return }
            self?.reloadIfNeeded()
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        offsetObserver = nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        reloadIfNeeded()
    }

    func display(_ viewModel: LoadMoreViewModel) {
        cell.message = viewModel.message
        cell.isLoading = viewModel.isLoading
        isRequestInFlight = viewModel.isLoading
    }

    private func reloadIfNeeded() {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        requestNextPage()
    }
}
```

Use `didEndDisplaying` to release observers and stale references. Cancel the page request only when the feature semantics require it.

Rules:
- guard duplicate requests
- hide or remove the load-more row/item when no next page exists
- use `didEndDisplaying` to release observers or stale UI references
- do not generate a load-more row/item when pagination is invisible or unnecessary

## Identity

Generate stable identity by default.

- Use domain identity when the same logical item survives refreshes.
- Do not generate fresh random identifiers on every update unless the row is intentionally transient.
- Preserve an existing controller for the same logical model when it owns meaningful UI state or in-flight work.

## Common Pitfalls

**Silent delegate failure** — A row controller conforms to `UITableViewDelegate` and implements `trailingSwipeActionsConfigurationForRowAt`. It compiles, tests pass, but swipe actions never appear. Root cause: the container does not forward that method. Fix: check the dispatch manifest before implementing any delegate method in a row controller.

**Force-unwrapping dequeued cells** — Two valid stances:

- **Force-unwrap + test coverage** (Essential Developer approach): registration errors are programmer mistakes that should crash immediately. Snapshot and integration tests exercise `cellForRowAt` — if registration is wrong, the test suite crashes, never ships. A `guard let` returning a blank cell is arguably worse: silent visual degradation in production that no test catches. This stance is valid when the dequeue path has comprehensive test coverage.
- **Defensive dequeue** (generic helper returning non-optional `T`): the dequeue helper itself handles the force-cast (`as! T`), so call sites use the result directly without `!`. Example: `let cell: MyCell = tableView.dequeueReusableCell()` → use `cell` as a local non-optional, assign to the weak `self.cell` separately.

Both are acceptable. Pick one and be consistent across the project. If using the force-unwrap stance, ensure every cell type has at least one test that triggers `cellForRowAt`.

**Stale cell reference** — A row controller holds `private var cell: MyCell?` for async updates. If `didEndDisplaying` or `prepareForReuse` does not nil it out, a later async callback writes to a reused cell showing different content.

**Identity drift** — Using `UUID()` as `CellController.id` on every refresh defeats diffable diffing. Items flash-reload instead of animating. Use domain identity (model ID) so the same logical item keeps its controller across updates.

**Over-applying the pattern** — A screen with one static cell type and no async work does not need row controllers. The indirection adds files and dispatch hops with zero benefit. See Warning Signs below.

## Generation Checklist

Run this checklist when generating new row/item controllers or modifying a container:

- [ ] Row controller conforms to `CellControllerDataSource` (or `ItemControllerDataSource`), NOT raw `UITableViewDataSource` — no `numberOfRowsInSection`
- [ ] Every delegate method the row controller implements is in the container's dispatch manifest
- [ ] If a new delegate method is needed, the container forwarding is added **and** the manifest is updated
- [ ] Cell reference is released on `didEndDisplaying` / reuse
- [ ] Async work is cancelled on `didEndDisplaying` / `cancelPrefetchingForRowsAt`
- [ ] Identity uses a stable domain value, not a transient `UUID()`
- [ ] Dequeued cells: either use local non-optional variable, or force-unwrap with test coverage on the `cellForRowAt` path
- [ ] The pattern is justified — the list actually has heterogeneous cells or per-row async lifecycle

## Warning Signs

The pattern is too heavy when:
- most controllers are one-line pass-through wrappers with no behavior
- the screen would be clearer with direct registrations and a small diffable data source
- protocols expand just to satisfy a few advanced sections
- trivial screens require jumping through many layers to debug basic behavior
- the container still contains a large `switch indexPath`

## UITableView Gotchas

### `sectionHeaderTopPadding` adds ~22pt above every sticky header (iOS 15+)

For `.plain` style tables, `UITableView.sectionHeaderTopPadding` defaults to `automaticDimension`, which inserts ~22pt of empty space **above** each section header. The header still sticks correctly — but as the user scrolls, rows pass *through* that empty band before reaching the header, reading as content bleeding above the sticky header.

**Symptom**: rows visibly slide above the sticky section header before disappearing behind it, even though the header has an opaque background.

**Fix**:

```swift
table.sectionHeaderTopPadding = 0
```

Leave the padding only if the design explicitly wants visual breathing room between sections (the system default is sized for grouped-style spacing aesthetics). For dense lists with cell-internal margins, zero is almost always correct.

### Sticky headers need opaque backgrounds

A sticky `.plain` section header floats over scrolling content. Any alpha < 1.0 lets row text show through; CSS `backdrop-filter` doesn't have a UIKit equivalent unless you put a `UIVisualEffectView` behind the header. For a clean sticky header, use a fully opaque solid background or a `UIVisualEffectView(effect: .systemThinMaterial)` wrapper — not `withAlphaComponent(0.95)`.

### Sticky header bleed is layered

When content appears visibly above a section header in a `.plain` table, the cause is usually one of three layers, in order of likelihood:

1. **Section header itself is translucent** (alpha < 1) — fix the header background
2. **`sectionHeaderTopPadding` gap above the header** — set to 0
3. **The cell is rendering inside the nav bar's vertical extent**, visible through a transparent nav bar appearance — fix at the nav bar layer (see `navigation-bar-appearance.md §Split Appearance for Opaque Chrome on iOS 26`)

Walk the layers from inside (header) outward (chrome). A fix at the wrong layer reduces the symptom without eliminating it; verify with the view debugger or `axe describe-ui` to confirm the actual cell frame vs. the table bounds before deciding which layer to touch.
