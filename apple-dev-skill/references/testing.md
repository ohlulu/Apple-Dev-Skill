# UIKit Testing Patterns

## Overview

For UIKit features, prefer tests that drive real view controllers and real views through UIKit lifecycle and user interactions. For general testing principles (test levels, async spies, assertion strategy, memory leak tracking), see [testing-principles.md](testing-principles.md).

## Default Testing Shape

When testing a UIKit screen:
- build the screen through its real composer/factory
- inject loader spies/stubs at the data boundary
- simulate lifecycle and user interactions through test helpers
- assert rendered UI state, not private implementation details

## Drive UIKit Through Real Lifecycle

Prefer simulating UIKit lifecycle over calling private methods directly.

Typical helpers:
- first appearance
- user-initiated refresh
- selection
- row becomes visible
- row stops being visible
- row becomes near-visible for prefetch
- row reuse

Minimal example:

```swift
extension UIViewController {
    func simulateAppearance() {
        loadViewIfNeeded()
        beginAppearanceTransition(true, animated: false)
        endAppearanceTransition()
    }
}
```

For list screens, add helpers on the concrete screen type so tests read in domain language rather than UIKit mechanics.

```swift
extension ListViewController {
    func simulateTapOnItem(at row: Int) {
        tableView.delegate?.tableView?(tableView, didSelectRowAt: IndexPath(row: row, section: 0))
    }
}
```

## Prefer Semantic Test Helpers

Test helpers should translate UIKit mechanics into feature language.

Prefer helpers like:
- `simulateUserInitiatedReload()`
- `simulateFeedImageViewVisible(at:)`
- `simulateTapOnFeedImage(at:)`
- `errorMessage`
- `numberOfRenderedComments()`

Avoid repeating raw index-path, control-event, and layout plumbing in every test.

## List Composition Test Helpers

Consider these shapes for list screens using `CellController` composition. Adapt names to the feature domain.

```swift
extension ListViewController {
    func numberOfRenderedItems(in section: Int) -> Int {
        tableView.numberOfSections > section ? tableView.numberOfRows(inSection: section) : 0
    }

    func itemView<T: UITableViewCell>(at row: Int, section: Int) -> T? {
        guard numberOfRenderedItems(in: section) > row else { return nil }

        let indexPath = IndexPath(row: row, section: section)
        return tableView.dataSource?.tableView(tableView, cellForRowAt: indexPath) as? T
    }

    @discardableResult
    func simulateItemVisible<T: UITableViewCell>(at row: Int, section: Int) -> T? {
        let indexPath = IndexPath(row: row, section: section)
        let view: T? = itemView(at: row, section: section)
        view.map { tableView.delegate?.tableView?(tableView, willDisplay: $0, forRowAt: indexPath) }
        return view
    }

    @discardableResult
    func simulateItemNotVisible<T: UITableViewCell>(at row: Int, section: Int) -> T? {
        let indexPath = IndexPath(row: row, section: section)
        let view: T? = simulateItemVisible(at: row, section: section)
        view.map { tableView.delegate?.tableView?(tableView, didEndDisplaying: $0, forRowAt: indexPath) }
        return view
    }

    func simulateItemNearVisible(at row: Int, section: Int) {
        tableView.prefetchDataSource?.tableView(tableView, prefetchRowsAt: [IndexPath(row: row, section: section)])
    }

    func simulateItemNotNearVisible(at row: Int, section: Int) {
        let indexPath = IndexPath(row: row, section: section)
        tableView.prefetchDataSource?.tableView?(tableView, cancelPrefetchingForRowsAt: [indexPath])
    }
}
```

For a visible load-more row, add a tiny helper layer instead of open-coding section/index-path details in each test.

```swift
extension ListViewController {
    func simulateLoadMoreAction(section: Int = 1) {
        guard let cell: LoadMoreCell = itemView(at: 0, section: section) else { return }

        let indexPath = IndexPath(row: 0, section: section)
        tableView.delegate?.tableView?(tableView, willDisplay: cell, forRowAt: indexPath)
    }

    func simulateTapOnLoadMoreError(section: Int = 1) {
        tableView.delegate?.tableView?(tableView, didSelectRowAt: IndexPath(row: 0, section: section))
    }

    var isShowingLoadMoreIndicator: Bool {
        loadMoreCell()?.isLoading == true
    }

    var loadMoreErrorMessage: String? {
        loadMoreCell()?.message
    }

    private func loadMoreCell(section: Int = 1) -> LoadMoreCell? {
        itemView(at: 0, section: section)
    }
}
```

## Reuse, Visibility, and Cancellation

For reusable list cells with async work, test these transitions explicitly:
- not visible → visible
- near-visible → visible
- visible → not visible
- visible again after reuse
- request completes after the old cell has been reused

These tests are especially valuable for image loading, prefetching, and pagination rows.

## Screen-Specific Testability Hooks

It is acceptable to add small test-only helper extensions to make tests readable and deterministic.

Good examples:
- simulate `UIControl` events from tests
- force a layout cycle before reading visible state
- expose computed properties for visible UI state in test helpers
- replace platform-sensitive controls with fakes when needed

If a real `UIRefreshControl` becomes hard to drive reliably on a given iOS version, consider swapping it with a tiny fake inside the test helper layer while preserving the existing target/action wiring.

Keep these helpers tiny, focused on behavior observation/simulation, and out of production code when possible.

## UIKit-Specific Test Guidance

All sections below assume the default testing shape: real composer, lifecycle simulation, rendered-state assertions. They describe **what** to test, not a different **how**.

### Pull-to-refresh
- test that refresh starts on first appearance if that is the feature behavior
- test that user-initiated refresh does not start a duplicate request while one is already running
- assert refresh indicator visibility while loading

### Navigation
- prefer asserting the pushed/presented screen type and visible state
- do not over-mock navigation controllers when a real navigation stack is easy to use in tests

### Pagination

Build through the real composer; simulate `willDisplay` for the load-more row; assert rendered item count and visible load-more state — not view-model properties.

Verify this flow:
1. simulate first appearance, complete the first page, assert rendered item count and whether a load-more row exists
2. simulate the load-more row becoming visible, assert the next-page request and loading indicator
3. complete load-more successfully, assert the combined rendered item count and that the loading indicator is hidden
4. complete load-more with an error, assert the error message while previously rendered items stay visible
5. simulate retry through tap or another visibility event, assert the error clears and duplicate requests are still prevented while loading
6. complete the last page, assert the load-more row disappears

### Scene composition
- test scene/window setup with a real `UIWindow` when possible
- assert key-and-visible behavior and root controller composition

### Frame-level layout tests

Host the view under test in a `UIWindow` (`isHidden = false`), never a bare `UIView` container. Outside a window, mutating a constraint's `constant` may not propagate through nested stacks at all — frames silently keep their old values and the test asserts against stale geometry.

Scope honestly: bugs that need production's multi-pass width churn (scroll view + split view + column settling) often do **not** reproduce in a simplified window harness — UIKit's automatic machinery works fine there. This holds even for high-fidelity harnesses: mounting the real view controller in a nav controller at exact production sizes with wide→narrow window resizes still self-heals. Do not burn cycles escalating harness fidelity; treat such frame tests as smoke-level invariants, document the behavioral contract at the fix site, and verify the real screen visually. Always test-the-test: confirm the assertion fails against the pre-fix code before trusting it as regression coverage.

## Async XCTestCase + Long-Lived Tasks (Xcode 26+)

Xcode 26 / Swift 6 strict concurrency aborts the test bundle in
`_swift_task_dealloc_specific` (SIGABRT) when an `async throws` test
method returns while any unstructured `Task` it spawned — directly or
transitively — still owns task-allocator pages.

Common trigger: a test builds a live VC through the real composer,
calls `simulateAppearance()`, and the view model spins up long-lived
observation `Task`s (GRDB change detection, paginated fetch,
notification listeners). The test asserts and returns; the Tasks have
not finished.

`addTeardownBlock` does not save you — teardown runs *after* the task
allocator's dealloc check.

**Fix:**
- Prefer `func test() throws` (synchronous) and drive async work with
  `XCTestExpectation` + `fulfill()` from the completion edge.
- If the test must be `async`, ensure every Task it spawned completes
  before the method returns: `await task.value` on each, or stop the
  observer synchronously before the last `await`.
- Cancel-and-forget is not enough — the Task must *finish*, not just be
  cancelled, for the allocator pages to be released in time.

**Crash signature:**
```
swift::_swift_task_dealloc_specific
static XCTSwiftErrorObservation._observeErrors(in:)
```

**Log signature:** test N reports `started`, the next line is test N+1
`started` (no `passed`/`failed` in between), then the bundle aborts.

## Warning Signs

The test strategy is drifting when:
- most tests mock UIKit instead of driving real screens
- tests depend on sleeps or timing guesses
- the same UIKit interaction plumbing is repeated across many tests
- async cell reuse bugs are left untested in screens that load data per row
