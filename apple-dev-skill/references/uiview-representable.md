# UIViewRepresentable Bridge Patterns

## Two Golden Rules

From Chris Eidhof's *Working With UIViewRepresentable* (the authoritative reference):

1. **UIKit → SwiftUI state: always defer asynchronously.** Delegate callbacks that modify SwiftUI `@State`/`@Binding` must never run synchronously during a render pass. Use `DispatchQueue.main.async` or `Task {}` to schedule the update on the next run-loop iteration.
2. **SwiftUI → UIKit view: only change what's needed.** `updateUIView` is called on every parent re-render. Blindly resetting all UIView properties triggers delegate callbacks, which modify state, which triggers another render — infinite loop.

Violating rule 1 produces the runtime warning *"Modifying state during view update, this will cause undefined behavior"*. Violating rule 2 produces infinite `updateUIView` calls.

## updateUIView — Diff, Don't Reset

```swift
// ❌ Resets everything every time
func updateUIView(_ map: MKMapView, context: Context) {
    map.removeAnnotations(map.annotations)
    map.addAnnotations(pins.map { PinAnnotation(pin: $0) })
    map.setRegion(region, animated: true)
}

// ✅ Diffs — only mutates what changed
func updateUIView(_ map: MKMapView, context: Context) {
    context.coordinator.syncAnnotations(new: pins) // add/remove delta only
    if context.coordinator.appliedGeneration != cameraGeneration {
        context.coordinator.appliedGeneration = cameraGeneration
        map.setRegion(region, animated: true)
    }
}
```

**Pattern**: Track "last applied" values on the coordinator. Compare in `updateUIView`. Only mutate the UIView when there's an actual difference.

### What triggers updateUIView?

Any `@State`, `@Binding`, `@Observable` property read during the parent view's `body`. Even siblings' state changes can cause re-evaluation. Assume `updateUIView` is called **frequently and unpredictably**.

## Delegate → SwiftUI State: Defer Async

```swift
// ❌ Synchronous — risks "modifying state during view update"
func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    parent.region = mapView.region  // fires during render pass → warning
}

// ✅ Deferred — runs after the current render pass
func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    let region = mapView.region
    Task { [weak self] in
        self?.onRegionChanged?(region)
    }
}
```

### When to use which deferral

| Technique | When |
|---|---|
| `Task {}` (from `@MainActor` context) | Swift 6+; inherits main actor, no `@Sendable` friction |
| `DispatchQueue.main.async` | Pre-Swift 6 or when ordering with other main-queue work matters |

## Coordinator Callback Pattern

The coordinator outlives any single `updateUIView` call. Store callbacks on the coordinator and refresh them in `updateUIView`:

```swift
struct MyMapView: UIViewRepresentable {
    var onRegionChanged: (MKCoordinateRegion) -> Void

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onRegionChanged = onRegionChanged
        // … diff-based updates …
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var onRegionChanged: ((MKCoordinateRegion) -> Void)?

        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = map.region
            Task { [weak self] in
                self?.onRegionChanged?(region)
            }
        }
    }
}
```

### Anti-pattern: stale `parent` capture

```swift
// ❌ parent is a value-type copy from makeCoordinator — immediately stale
class Coordinator {
    var parent: MyMapView  // captured at makeCoordinator time
    func mapView(…) {
        parent.onRegionChanged(…)  // calls old closure
    }
}
```

This works only if you update `coordinator.parent = self` at the top of `updateUIView`. But extracting individual callbacks is clearer and avoids accidentally accessing stale properties.

## Distinguishing Programmatic vs User Changes

Many UIKit views fire the same delegate callback for both programmatic mutations and user gestures (MKMapView, UIScrollView, UITextView). To distinguish:

```swift
class Coordinator {
    var pendingProgrammaticChanges = 0

    // In updateUIView — before programmatic mutation:
    func applyRegion(_ region: MKCoordinateRegion, on map: MKMapView) {
        pendingProgrammaticChanges += 1
        map.setRegion(region, animated: true)
    }

    // In delegate callback:
    func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
        let isProgrammatic = pendingProgrammaticChanges > 0
        if isProgrammatic { pendingProgrammaticChanges -= 1 }
        // Only update "user has interacted" flags when !isProgrammatic
    }
}
```

This prevents programmatic fits from falsely triggering "user moved camera" flags.

## Pre-Rendered Bitmaps for Scroll/Pan Performance

When a UIViewRepresentable manages many visual elements (map annotations, floating markers), and each element has a complex view hierarchy (shadows, rounded corners, images, badges), **pre-render the element as a flat `UIImage`** and set it on the native view's `.image` property.

### Why

| Approach | Cost per frame during scroll |
|---|---|
| Live SwiftUI `_UIHostingView` per element | Full layout + render + environment propagation |
| Live `UIView` subclass with sublayers | Auto Layout + shadow rasterization |
| Pre-rendered `UIImage` on recycled view | Zero — bitmap blit only |

### When to pre-render

- The element has ≥3 visual layers (background + image + badge/shadow)
- There are ≥10 elements visible simultaneously during scroll/pan
- The element's appearance is determined by data that changes infrequently (not every frame)

### Pattern

```swift
enum ElementRenderer {
    static func render(image: UIImage?, badge: Int?) -> UIImage {
        let size = CGSize(width: 66, height: 48)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            // 1. Shadow
            ctx.cgContext.setShadow(offset: …, blur: …, color: …)
            // 2. Background shape
            UIColor.white.setFill()
            UIBezierPath(roundedRect: …).fill()
            // 3. Clear shadow, draw content
            ctx.cgContext.setShadow(offset: .zero, blur: 0)
            image?.draw(in: …)
            // 4. Optional badge overlay
            if let badge { drawBadge(badge, in: …) }
        }
    }
}
```

Cache the rendered images by content identity (e.g., `"{imagePath}_pin"`). Use a separate `NSCache` from the raw thumbnail cache — these are final composited bitmaps, not source images.

### Async image loading with view identity guard

When views are recycled (MKAnnotationView, UICollectionViewCell), async-loaded images may arrive after the view has been reused for different content:

```swift
Task { [weak view, expectedId = item.id] in
    let image = await loadThumbnail(…)
    guard let view,
          (view.model as? MyItem)?.id == expectedId
    else { return }
    view.image = rendered
}
```

Always verify the view still represents the same data before applying the async result.

## Swift 6 Concurrency

### `@preconcurrency` for ObjC delegate protocols

UIKit delegate protocols (MKMapViewDelegate, UIScrollViewDelegate, etc.) may not have full `@MainActor` annotations. When the coordinator is `@MainActor` (from `defaultIsolation` or explicit annotation), use `@preconcurrency` to suppress isolation mismatch:

```swift
final class Coordinator: NSObject, @preconcurrency MKMapViewDelegate { … }
```

This is safe because UIKit guarantees main-thread delivery for all delegate callbacks.

### Async work in coordinators

Use `@concurrent` (Swift 6.1+) or `nonisolated` for functions that perform heavy work (image decode, data processing) off the main thread:

```swift
@concurrent
func loadThumbnail(from storage: ImageStorageService, path: String) async -> UIImage? {
    // Runs on cooperative pool, not main actor
}
```

