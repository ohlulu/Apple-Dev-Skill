# Card Zoom Transition (Card → Floating Detail)

## When to Apply

A tapped card — a thumbnail plus text — opens a detail whose content differs from the card, and the detail should grow out of the card and shrink back into it: a product card opening a product detail, a summary card opening its full list.

Builds on [zoomable-image-preview](zoomable-image-preview.md) and does not repeat it: `.overFullScreen` presentation (Fact 1), snapshot geometry in `transitionContext.containerView` and hiding the source by `alpha` (Fact 4), a manual follow-finger dismiss instead of `UIPercentDrivenInteractiveTransition` (Fact 5), and pan / scroll-view coexistence (Fact 6). Read those first.

Not for: an image viewer whose source and destination are the same picture — that is zoomable-image-preview alone. Everything below exists because the two sides show *different* content.

## Prefer the Native Zoom Where It Fits

iOS 18's `preferredTransition = .zoom(options:sourceViewProvider:)` supplies the interruptible transition, the interactive dismiss gestures, and `ZoomOptions.alignmentRectProvider` for free. Build the transition yourself only when one of its limits applies:

- **Full screen only on iOS 18.** A sheet presentation is forced to full screen, and during the transition the system puts an opaque background behind the destination — a floating, dimmed-backdrop card is not expressible ([Douglas Hill, "Zoom transitions"](https://douglashill.co/zoom-transitions/)).
- **iOS 26 widens sources for sheets to bar button items** ([WWDC25 "Build a UIKit app with the new design"](https://developer.apple.com/videos/play/wwdc2025/284/)). Verify a sheet zooming from an arbitrary cell on the target OS before depending on it.
- **Deployment target below iOS 18.** The API does not exist; maintaining a native path plus a custom fallback doubles the motion code to keep consistent.

## One Placement Model for Everything on the Surface

Move every view on the growing surface — the detail content and the source snapshot alike — with a uniform scale plus a top-left origin, applied as a transform. Never lay the detail out at its final size and let the growing surface clip it: the clipped detail then shows its centre region at full scale while the snapshot shows the whole card at card scale, and the crossfade blends two pictures at unrelated sizes and positions. A transform is also the only way a `snapshotView(afterScreenUpdates:)` result scales its rendered content; a frame change does not.

```swift
struct Placement: Equatable {
  var scale: CGFloat
  var origin: CGPoint        // top-left of the scaled frame, in surface coordinates

  static let resting = Placement(scale: 1, origin: .zero)

  static func widthFit(_ size: CGSize, toWidth width: CGFloat) -> Placement {
    Placement(scale: size.width > 0 ? width / size.width : 1, origin: .zero)
  }

  /// Scales `focus` (view coordinates) to cover `target` (surface coordinates), centres aligned.
  static func covering(_ focus: CGRect, target: CGRect) -> Placement {
    let s = max(target.width / focus.width, target.height / focus.height)
    return Placement(scale: s, origin: CGPoint(x: target.midX - focus.midX * s, y: target.midY - focus.midY * s))
  }

  /// Keeps a second view glued to one moving from `anchor` to `self`; identity when `self == anchor`.
  func relative(to anchor: Placement) -> Placement {
    let r = scale / anchor.scale
    return Placement(scale: r, origin: CGPoint(x: origin.x - anchor.origin.x * r, y: origin.y - anchor.origin.y * r))
  }

  func apply(to view: UIView) {
    let size = view.bounds.size
    view.transform = CGAffineTransform(scaleX: scale, y: scale)
    view.center = CGPoint(x: origin.x + size.width * scale / 2, y: origin.y + size.height * scale / 2)
  }
}
```

- **Present:** content starts at the placement over the source (next section), animates to `.resting`; the snapshot starts at `.resting` (it *is* the card) and animates to `Placement.resting.relative(to: start)`.
- **Dismiss:** content starts at its current placement and animates to the placement over the source; the snapshot starts at `current.relative(to: end)` and animates to `.resting`.
- **Why the snapshot never drifts:** both views interpolate linearly between their end points, so their scale ratio stays constant and a given picture point stays on the same surface point at every frame. Unit-test this with a few interpolation steps rather than trusting a screen recording.
- **Dismiss from a drag:** the drag scales the whole surface by transform. Bake that transform into the surface frame, then set the content to `widthFit(bakedFrame.width)` — resetting the content to identity at the handoff shows it at full size, clipped, for one frame.
- **Layout passes while frozen:** while a transition or drag owns the placement, `viewDidLayoutSubviews` may update the content's `bounds` only. Re-centring it undoes the alignment mid-flight.

## Align a Focus, Not Just the Frame

Matching widths is not enough: the detail's image sits below its own header and is cropped to a different aspect ratio than the card's thumbnail, so the two images still land offset and crossfade as a double exposure. Let the source name a focus (the card's photo view) and the destination its counterpart (the detail's hero image), and place the content so the counterpart **covers** the focus — the same idea as `ZoomOptions.alignmentRectProvider`.

- **Cover, centres aligned.** `covering` scales by the larger ratio, like an aspect-fill image view, so no strip of the card photo is left uncovered; the surface clips the overflow. With both images aspect-filling around their centres, the two line up pixel for pixel only when both boxes crop the same dimension of the picture — for a 4:3 detail image over a square thumbnail, pictures at least 4:3 wide; squarer or portrait pictures differ by the crop, which is what the short crossfade window below absorbs.
- **Fall back to `widthFit`** when either side has no focus, or when the destination focus is scrolled out of sight (its rect, converted into the content view, does not intersect the content's bounds). Aligning to an image the user cannot see drags the visible content off the surface.
- **Resolve both rects at transition time.** Convert the destination focus into the content view after the sheet's layout pass, and the source focus into the source view; a cached rect is stale after scrolling or a reload.

## Crossfade on Its Own Linear Animator

- **Run geometry and crossfade on separate animators of the same duration.** Geometry on the spring; the snapshot-out / content-in crossfade on a `.linear` `UIViewPropertyAnimator` whose block nests `UIView.animateKeyframes(withDuration: 0, …)` to confine the fade to a window. Keyframes nested directly in a spring animator do not land at their relative times — a 15 % window was observed running with the surface already near full size (iOS 26.5 simulator). WWDC17 "Advanced Animations with UIKit" (View Morphing) splits transform and alpha across animators the same way, and its keyframe example nests them in a linear animator.
- **Keep the window where the surface is still small** — suggest finishing the swap within the first ~15 % of a present and starting it no earlier than ~75 % of a dismiss. The spring covers most of the distance early, and even aligned, text on the card and in the detail never coincides; a crossfade over a large surface reads as a double exposure no matter how well the photos match.
- **Stop both animators on every interruption** — a close during the present, a drag taking over, the sheet disappearing without the animators — and finish both from any test seam that jumps a transition to its end.

## Source Lookup Traps

- **Flush a pending reload before `cellForItem(at:)`.** `reloadData()` defers the reload to the next layout pass; until then `visibleCells` is empty and `cellForItem(at:)` returns `nil` even though the cell views are still on screen. The source provider runs at moments UIKit chooses, often right after the list's own observers reloaded, so without `collectionView.layoutIfNeeded()` first the zoom silently degrades to the missing-source fallback. Cover it with a test that calls `reloadData()` and then resolves the source.
- **The re-resolved source can be a different view.** Looking the cell up again on every call (the WWDC24 advice) means the dismissal may find a reused or reloaded cell rather than the instance hidden at presentation. Restore the previously hidden view's alpha before hiding the new one, or the first instance stays invisible after being reused for another item.
- **Pass the view that owns the rounded corners** — the card's background view, not the cell or its `contentView` — so the surface's starting corner radius and the snapshot's outline match what the user tapped.
