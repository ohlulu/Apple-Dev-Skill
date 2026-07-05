# Composer / Screen Composition Patterns

## Overview

Use a dedicated composer or factory when a UIKit screen needs more wiring than a plain initializer.

Goal:
- instantiate the screen in one place
- keep `UIViewController` focused on rendering and user events
- build the UI hierarchy inside the screen type in code
- wire loaders, callbacks, and navigation handlers at the edge
- return a ready-to-display controller
- keep scene/root composition thin

## Decision Rule

### Consider a composer when the screen has:
- programmatic UI setup plus dependency injection
- two or more external collaborators
- callback wiring such as `onRefresh`, retry, or selection
- UI-specific adapters or row controllers to create
- scene-level root composition in `SceneDelegate` or `AppDelegate`

### Prefer direct initialization when the screen has:
- one simple dependency
- an initializer that already expresses the full setup clearly
- no callback wiring
- no scene/root setup beyond `UIViewController()` or `UINavigationController(rootViewController:)`

## What the Composer Owns

A composer typically owns:
- instantiating the screen
- setting title or navigation items that belong to composition time
- creating UI-specific adapters or bridges
- wiring controller callbacks to those adapters
- injecting navigation closures
- returning the fully wired controller

A composer typically does **not** own:
- business rules
- persistence or network policy
- view rendering logic
- building subviews or constraints itself
- starting side effects during composition

## Screen Composer Skeleton

Consider this shape when a UIKit screen is code-built and needs callback wiring.

```swift
@MainActor
public final class FeedUIComposer {
    private init() {}

    public static func feedComposedWith(
        feedLoader: @escaping () async throws -> Paginated<FeedImage>,
        imageLoader: @escaping (URL) async throws -> Data,
        selection: @escaping (FeedImage) -> Void = { _ in }
    ) -> ListViewController {
        let controller = makeFeedViewController(title: "Feed")
        let adapter = FeedLoaderAdapter(
            controller: controller,
            feedLoader: feedLoader,
            imageLoader: imageLoader,
            selection: selection
        )

        controller.onRefresh = adapter.loadResource
        return controller
    }

    private static func makeFeedViewController(title: String) -> ListViewController {
        let controller = ListViewController()
        controller.title = title
        return controller
    }
}
```

`FeedLoaderAdapter` stands for the UI-specific bridge between controller callbacks and the injected loaders. The composer creates that bridge, but the bridge owns the loading flow.

If the screen is a plain `UIViewController` subclass, initialize it directly and let that type build its hierarchy in `viewDidLoad()` or a dedicated `setupUI()` path.

## Navigation Wiring

Selection-driven navigation is often easiest to compose as a closure injected into the screen.

In the sample above, `selection` is the navigation seam:

```swift
let adapter = FeedLoaderAdapter(
    controller: controller,
    feedLoader: feedLoader,
    imageLoader: imageLoader,
    selection: selection
)
```

The controller reports the user event. The injected closure decides whether that event pushes, presents, or does something else. This keeps navigation decisions outside the view controller while still making the wiring explicit at composition time.

### Callback Shape

Navigation closures should carry data out, not pass callbacks back in.

**Avoid closure-of-closures** — a navigation closure whose parameters include one or more `@escaping` callback closures. This creates nested callback chains that are hard to read, hard to extend, and tightly couple the controller to the coordinator's wiring.

```swift
// BAD — 3 nested callbacks inside a navigation closure
var onAddField: ((_ definitions: [FieldDefinition],
                  _ onSelect: @escaping (Int64) -> Void,
                  _ onCreated: @escaping (FieldDefinition, String) -> Void,
                  _ onDeleted: @escaping (Int64) -> Void) -> Void)?
```

**Use a sum type** when a child screen can produce multiple distinct results. Collapse N callbacks into one `(Result) -> Void`.

```swift
enum AddFieldResult {
    case selected(definitionId: Int64)
    case customCreated(definition: FieldDefinition, initialValue: String)
    case definitionDeleted(id: Int64)
}

var onAddField: ((_ definitions: [FieldDefinition],
                  _ onResult: @escaping (AddFieldResult) -> Void) -> Void)?
```

Benefits: exhaustive switch catches missing cases, adding a new action is one enum case, and both VC and coordinator read linearly.

**Threshold:** a single callback parameter (e.g., `onNoteContent: @escaping (String) -> Void`) is acceptable. Two or more → extract a result enum.

## Scene Root Composition

When a scene needs a root navigation stack plus child-screen composition, keep that wiring in the scene layer and delegate each screen to its composer.

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private lazy var navigationController = UINavigationController(
        rootViewController: FeedUIComposer.feedComposedWith(
            feedLoader: feedService.loadFeed,
            imageLoader: feedService.loadImageData,
            selection: showComments
        )
    )

    func configureWindow() {
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }

    private func showComments(for image: FeedImage) {
        let controller = CommentsUIComposer.commentsComposedWith(
            commentsLoader: { try await feedService.loadComments(for: image) }
        )

        navigationController.pushViewController(controller, animated: true)
    }
}
```

The scene layer decides navigation structure. Each screen composer decides how its own screen is instantiated and wired.

## Hard Rules

- Do not trigger loaders during composition. Wait for lifecycle or user action.
- Avoid retain cycles when wiring closures back into navigation or loaders.
- Keep view hierarchy creation inside the screen type; the composer should choose initializers and wiring, not assemble subviews.
- Return a controller that is ready to display without more external mutation.

## Testability

Composers are easiest to verify through wiring tests:
- assert the returned controller type
- assert the title or root navigation structure
- simulate user actions on the composed screen instead of calling adapter internals
- keep scene composition tests at the scene/root level

## Generation Checklist

Before shipping a new composer or navigation wiring:

- [ ] Composer justified — the screen has ≥2 collaborators, callback wiring, or adapters (otherwise direct init)
- [ ] No loaders triggered during composition — side effects wait for lifecycle or user action
- [ ] View hierarchy built inside the screen type, not the composer
- [ ] Navigation closures carry data out; ≥2 callback parameters → collapsed into one result enum
- [ ] No retain cycles in closure wiring (weak references where closures point back)
- [ ] Returned controller is display-ready without further external mutation

## Warning Signs

The composition boundary is drifting when:
- `SceneDelegate` manually wires row controllers or per-cell logic
- a view controller fetches app dependencies directly
- the composer starts rendering or mapping view models itself
- the same controller initialization and callback wiring is duplicated across call sites
- a navigation closure accepts two or more `@escaping` callback parameters (closure-of-closures)
