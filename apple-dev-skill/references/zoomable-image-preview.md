# Zoomable Image Preview with Hero Transition + Pan Dismiss

## When to Use

Tap-to-enlarge avatar / image with these traits, taken together:

- Source is a small circular (or rounded) image somewhere in the UI.
- Tap presents a full-screen viewer with a frosted-glass / dim backdrop.
- Hero growth: source view morphs into the centred preview.
- Inside the viewer: pinch zoom, double-tap zoom, pan around when zoomed.
- Dismiss: pan-down follows the finger (IG / Telegram / WhatsApp / Photos.app feel) — preview shrinks back into the source, never slides off-screen.

If the requirement is only "show a bigger image full-screen", a plain modal with `UIImageView` is enough. This page is for the case where the *motion* between source and preview matters and the viewer is interactive.

Not for: navigation push transitions (use `UINavigationController`'s built-in), photo browser libraries (use a vendored library — INSPhotoGallery / SKPhotoBrowser).

## Architecture Skeleton (Five Pieces)

```
HeroSource (protocol)            ──►  PreviewVC
  • heroFrame(in: coord) -> Rect       • UIScrollView + UIImageView
  • heroImage: UIImage?                • pinch / double-tap zoom
  • heroCornerRadius: CGFloat          • manual pan-to-dismiss
  • heroIsHidden: Bool { get set }     • holds TransitioningDelegate strongly

PresentAnimator  ──┐                   DismissAnimator (close button only)
                   ├── TransitioningDelegate ─► .overFullScreen present
                   │                                (NEVER .custom)
ManualPanGesture ──┘  (NOT UIPercentDrivenInteractiveTransition)
```

The pan gesture is **deliberately outside** UIKit's interactive transitioning protocol. UIPercentDrivenInteractiveTransition only scrubs two fixed states linearly — it cannot express the multi-axis follow-finger feel of IG / Photos.app where horizontal damping, scale, blur fade, and pan position move independently.

## Contracts + Wiring

What each piece must guarantee, and who owns whom. Skip these and the implementation looks correct but leaks the source view, drops the animator mid-flight, or orphans snapshots.

### Piece Contracts

**`HeroSource` protocol** — anything that can act as the originating view.

```swift
@MainActor protocol HeroSource: AnyObject {
  func heroFrame(in coordinateSpace: UICoordinateSpace) -> CGRect
  var heroImage: UIImage? { get }
  var heroCornerRadius: CGFloat { get }
  var heroIsHidden: Bool { get set }   // implement as alpha = 0 / 1
}
```

- `heroIsHidden` MUST be `alpha`-based, not `isHidden`. `isHidden = true` triggers a layout pass in any containing stack view, which jitters the source frame between snapshot creation and the hero animation starting.
- `heroIsHidden = false` MUST be restored in **three** places, all of which are easy to miss: present cancel completion, dismiss commit completion (pan), dismiss animator completion (close button). Forgetting any one leaves the source invisible on the original screen.

**Source adapter** — extension on the actual source view (e.g. `AvatarImageView`) that conforms to `HeroSource`. Lives on the source view's lifetime; the preview holds only a `weak` reference.

**`PreviewVC`** — the modal viewer.

- Owns the `TransitioningDelegate` `strong`. UIKit's `transitioningDelegate` property is `weak`; if you let the delegate go out of scope the animator dies mid-transition and the modal renders blank.
- Holds the `HeroSource` `weak`.
- `viewDidLayoutSubviews` runs `layoutPreviewImage` which must be **idempotent** — it fires multiple times during the transition and on rotation; only changing state when needed avoids re-inflating bounds (Fact 2 Trap A).
- Pan gesture attached to `self.view`, NOT `scrollView` (see Fact 6 for the coexistence rules).
- Pan snapshot lives in `self.view`, NOT `window`. View ownership means `dismiss(animated: false)` collects the snapshot automatically; window ownership requires manual cleanup that's easy to leak.

**`PresentAnimator` / `DismissAnimator`** — one short-lived instance per transition, created by the delegate.

- Hold `HeroSource` `weak` (its real owner outlives the animator).
- Build the moving snapshot in `transitionContext.containerView`, not `self.view`.
- Restore `source.heroIsHidden = false` on `transitionWasCancelled` for present; always on completion for dismiss.

**`TransitioningDelegate`** — a plain `NSObject` conforming to `UIViewControllerTransitioningDelegate`. Implements `animationController(forPresented:…)` and `animationController(forDismissed:)`. Does NOT implement `interactionControllerForDismissal` — pan dismiss is manual (Fact 5).

### Ownership Graph

```
  UIKit                                                    Source screen
    │ weak                                                       │
    ▼                                                            ▼
  PreviewVC.transitioningDelegate                          HeroSource view
    │                                                            ▲
    │ strong (PreviewVC owns it; UIKit only weak-refs)           │ weak
    ▼                                                            │
  TransitioningDelegate ── creates one─per─transition ──────────│
    │                                                            │
    ├──► PresentAnimator ────────────────────────────────┘
    └──► DismissAnimator (close button only)
```

Key points the graph encodes:
- PreviewVC → TransitioningDelegate is **strong** (UIKit's `weak` reference is the trap).
- TransitioningDelegate → HeroSource is **weak** (HeroSource's owner is the source screen, not us).
- Animators are not retained across transitions — they hold their own weak source reference.

### Pan Handler State Contract

| State | Must do | Must NOT do |
|---|---|---|
| `.began` | (1) Tear down any stale snapshot + in-flight animations from a previous gesture. (2) Build snapshot at `previewImageView.convert(bounds, to: view)`. (3) Hide `previewImageView` + closeButton. (4) Reset `backdropAlpha = 1`. | Touch `scrollView.contentOffset` / `zoomScale`. Recreate state if `panSnapshot` is already non-nil with the same identity. |
| `.changed` | Update `snapshot.transform` from `(max(0, translation.y), translation.x * 0.5)` with scale `1 - progress*0.4`. Set `backdropAlpha = 1 - progress`. | Recreate the snapshot. Move `previewImageView`. |
| `.ended` / `.cancelled` / `.failed` | Decide commit vs cancel using `progress >= 0.35 OR velocity.y > 900`. Commit: animate snapshot to source frame + radius, then `dismiss(animated: false)`. Cancel: spring back to identity. | Call `dismiss(animated: true)` (stacks a second animation). Skip the `panSnapshot === snapshot` identity guard in completions. |

### Acceptance Checklist

Run all seven before declaring done. The implementation can look correct and still fail any of these silently.

- [ ] **Initial centring**: open preview — image is centred both axes, no offset to top / bottom / either side.
- [ ] **Pinch round-trip**: pinch in, pan around the zoomed image, pinch back to min — image returns to the same centred position as the initial open.
- [ ] **Cancel pan**: drag down ~80pt and release — snapshot springs back to centred resting position, backdrop opacity restores, previewImageView and close button visible again.
- [ ] **Commit pan (drag)**: drag down past 35% of the threshold — snapshot animates smoothly to the source avatar's frame, no flash, no second animation playing on top, dismiss completes.
- [ ] **Commit pan (flick)**: short fast downward flick (< 35% drag, > 900pt/s velocity) — same smooth dismiss as above.
- [ ] **Close button**: tap X — dismiss animator runs (snapshot grows in reverse from preview to source), backdrop fades, source visible again.
- [ ] **Source restoration**: after every dismiss path (close button, pan commit, pan-cancel-then-close) — source view's `alpha == 1` in the original screen. Open + dismiss 5× in a row; check the view debugger for orphan snapshots or duplicate transitioning delegate retained.

Fail any check → hit the matching trap in Facts & Mechanisms or the Anti-Pattern Table below.

## Facts & Mechanisms

### Fact 1: `modalPresentationStyle = .overFullScreen`, never `.custom`

For a viewer with a `UIVisualEffectView` backdrop that should blur the presenting screen:

- `.custom` (without supplying a `UIPresentationController`) **detaches the presenter view from the window** once the transition completes. `UIVisualEffectView` can only blur views that are *actually behind it in the render tree*; with nothing behind, it renders as a flat grey panel and users report "the blur is broken".
- `.overFullScreen` keeps the presenter in the hierarchy. Custom `transitioningDelegate` still works. Blur picks up the presenter's content.

Also set `modalPresentationCapturesStatusBarAppearance = true` so the viewer's status bar style (white on dark blur) takes precedence.

### Fact 2: Centring a Zoom-Target Image — Use `contentInset`, NOT Manual `center` / `frame.origin`

Centring a zoom-target image in `UIScrollView` is one of the most-bugged patterns in UIKit. Two mechanisms cause it:

**Trap A — writing `frame` under a non-identity transform inflates `bounds`.**

`UIScrollView` applies `CGAffineTransform(scaleX: zoomScale, y: zoomScale)` to the zoom view. UIView's documented contract: *"If the transform property is not the identity transform, the value of the frame property is undefined and should not be modified."* Observed behavior on iOS 17–26: UIKit back-translates the requested `frame.size` through the transform and inflates `bounds.size` to compensate.

```
Before: imageView.bounds.size = (1536, 1536), transform.a = 0.262
        → visual frame.size = 402

After:  imageView.frame = CGRect(.zero, size: 1536x1536)
        → bounds.size = 5868   ← UIKit set this so 5868 × 0.262 = 1536
        → all subsequent size math is wrong
```

**Trap B — `UIScrollView.layoutSubviews()` resets the zoom view's origin to (0, 0) on every layout pass.**

UIScrollView assumes its zoom view sits at content origin (0, 0). Any manual `previewImageView.center = …` survives at most one frame before the next layout pass undoes it — geometry logging shows a manually-set `center = (201, 437)` reset to `(201, 201)` between two consecutive `viewDidLayoutSubviews` calls with no application code running in between.

**The fix — work *with* `UIScrollView` instead of against it:**

```swift
// In layoutPreviewImage (idempotent across multiple viewDidLayoutSubviews):
if previewImageView.bounds.size != imageSize {
  previewImageView.bounds.size = imageSize   // bounds is transform-safe
}
scrollView.contentSize = imageSize
let fitScale = min(view.bounds.width / imageSize.width,
                   view.bounds.height / imageSize.height)
scrollView.minimumZoomScale = fitScale
scrollView.maximumZoomScale = fitScale * 4
if abs(scrollView.zoomScale - fitScale) > 0.0001 {
  scrollView.zoomScale = fitScale   // fires scrollViewDidZoom
}
snapContentOffsetToCenterIfAtRest()

// In scrollViewDidZoom:
private func centerContent() {
  let scrollSize = scrollView.bounds.size
  let contentSize = previewImageView.frame.size   // reading frame.size is OK
  let hInset = max(0, (scrollSize.width  - contentSize.width)  / 2)
  let vInset = max(0, (scrollSize.height - contentSize.height) / 2)
  scrollView.contentInset = UIEdgeInsets(top: vInset, left: hInset,
                                         bottom: vInset, right: hInset)
}

// At rest only — pinch focus must stay under the finger while zooming.
private func snapContentOffsetToCenterIfAtRest() {
  let scrollSize  = scrollView.bounds.size
  let contentSize = previewImageView.frame.size
  guard contentSize.width  <= scrollSize.width  + 0.5,
        contentSize.height <= scrollSize.height + 0.5 else { return }
  let inset  = scrollView.contentInset
  let target = CGPoint(x: -inset.left, y: -inset.top)
  if !pointsApproximatelyEqual(scrollView.contentOffset, target) {
    scrollView.setContentOffset(target, animated: false)
  }
}

// On pinch end — snap back to centred resting position.
func scrollViewDidEndZooming(_ scrollView: UIScrollView,
                             with view: UIView?, atScale scale: CGFloat) {
  snapContentOffsetToCenterIfAtRest()
}
```

Why each piece:

- `bounds.size =` not `frame =` — sidesteps Trap A.
- Symmetric `contentInset` — pads the viewport so content lands in the middle when it fits.
- Explicit `contentOffset = (-inset.left, -inset.top)` — `UIScrollView` does **not** auto-shift offset to honour inset; the natural offset (0, 0) puts content at `(inset.left, inset.top)` = top-left corner of viewport, not centre.
- `scrollViewDidEndZooming` snap — after a pinch round-trip back to min zoom, scrollview leaves the offset wherever the pinch focus happened to land. Snap restores the original centred position.
- Asymmetric `inset(top: vInset, left: hInset, bottom: 0, right: 0)` ALSO centres at rest with `contentOffset = (0, 0)`, but the symmetric form survives pinch drift correctly — prefer it.

### Fact 3: Circular Mask Scales with the Zoom Transform

For a circular preview that stays circular at any zoom level:

```swift
previewImageView.layer.cornerRadius = min(image.size.width, image.size.height) / 2
previewImageView.clipsToBounds = true
```

`cornerRadius` lives in the layer's local coordinate space. UIScrollView's zoom is a *layer transform* on the same view — both `bounds` and `cornerRadius` are visually scaled by the same factor. The visible corner radius is always `cornerRadius × zoomScale` = `(min(w,h) / 2) × zoomScale` = `min(visualW, visualH) / 2` → a perfect circle at every zoom.

This is also how the hero snapshot stays circular through the entire growth animation — animate `snapshot.layer.cornerRadius` from `source.heroCornerRadius` to `min(targetFrame.w, targetFrame.h) / 2`.

### Fact 4: Hero Snapshot in `transitionContext.containerView` Coordinates

```swift
// Inside present animator's animateTransition(using:)
let container = transitionContext.containerView
let snapshot  = UIImageView(image: source.heroImage)
snapshot.contentMode    = .scaleAspectFill
snapshot.clipsToBounds  = true
snapshot.layer.cornerRadius = source.heroCornerRadius
snapshot.frame = source.heroFrame(in: container)   // ← container, NOT window
container.addSubview(snapshot)

source.heroIsHidden = true   // alpha = 0, NOT isHidden = true
// (isHidden = true triggers layout invalidation in stack views; alpha avoids it)

UIView.animate(withDuration: duration, ...) {
  snapshot.frame = targetFrame
  snapshot.layer.cornerRadius = min(targetFrame.width, targetFrame.height) / 2
  // also fade in blur, dim, chrome here
} completion: { _ in
  snapshot.removeFromSuperview()
  if transitionContext.transitionWasCancelled {
    source.heroIsHidden = false   // MUST restore on cancel
  }
  transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
}
```

Three things that matter:

- **Coordinate space**: `source.convert(bounds, to: containerView)`, not `to: window`. `containerView` is what the snapshot lives in; `window` will diverge under rotation / safe-area changes / Stage Manager.
- **Hide source via `alpha`, not `isHidden`**: `isHidden = true` triggers a layout invalidation in containing stack views, which jitters the source frame between snapshot creation and animation start. `alpha = 0` is a pure rendering toggle.
- **Restore on cancel**: if the present transition is cancelled (interruption, programmatic dismiss-during-present), `heroIsHidden = false` must run. Without it the source stays invisible.

### Fact 5: Manual Pan Dismiss, Not `UIPercentDrivenInteractiveTransition`

`UIPercentDrivenInteractiveTransition` scrubs a single fixed animation linearly from start to end. It cannot express:

- Vertical translation 1:1 + horizontal translation damped to 0.5
- Scale 1.0 → 0.6 proportional to drag distance
- Backdrop blur fading independently of position
- "Cap translation at the source frame" — if the finger drags 1000pt down, the percent driver pushes the snapshot off-screen

IG / Photos.app pattern: handle the pan **directly**, animate the snapshot manually, dismiss `animated: false` once the snapshot reaches the source frame.

```swift
@objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
  let translation = gesture.translation(in: view)
  let velocity    = gesture.velocity(in: view)

  switch gesture.state {
  case .began:
    beginPanDismiss()
  case .changed:
    guard let snapshot = panSnapshot else { return }
    updatePanDismiss(snapshot: snapshot, translation: translation)
  case .ended, .cancelled, .failed:
    guard let snapshot = panSnapshot else { return }
    let progress = max(0, min(1, translation.y / 220))
    let commit = progress >= 0.35 || velocity.y > 900
    commit ? commitPanDismiss(snapshot: snapshot)
           : cancelPanDismiss(snapshot: snapshot)
  default: break
  }
}

private func updatePanDismiss(snapshot: UIImageView, translation: CGPoint) {
  let dragY    = max(0, translation.y)   // ← clamp upward jitter
  let progress = max(0, min(1, dragY / 220))
  let scale    = 1 - progress * 0.4
  snapshot.transform = CGAffineTransform(
    translationX: translation.x * 0.5,   // horizontal damped
    y: dragY                              // vertical 1:1
  ).scaledBy(x: scale, y: scale)
  setBackdropAlpha(1 - progress)
}

private func commitPanDismiss(snapshot: UIImageView) {
  let targetFrame  = heroSource?.heroFrame(in: view) ?? panStartFrame
  let targetRadius = heroSource?.heroCornerRadius ?? 0
  UIView.animate(withDuration: 0.28,
                 options: [.curveEaseInOut, .beginFromCurrentState]) {
    snapshot.transform        = .identity
    snapshot.frame            = targetFrame
    snapshot.layer.cornerRadius = targetRadius
    self.setBackdropAlpha(0)
  } completion: { [weak self] _ in
    guard let self else { return }
    self.heroSource?.heroIsHidden = false
    self.dismiss(animated: false) {       // ← animated: false, NOT true
      snapshot.removeFromSuperview()
      if self.panSnapshot === snapshot {  // ← re-entry guard
        self.panSnapshot = nil
      }
    }
  }
}
```

The key invariants:

- **Pan-during-animation re-entry**: the user can start a second pan during the first one's spring-back. `commitPanDismiss` / `cancelPanDismiss` completions must check `if self.panSnapshot === snapshot` before mutating shared state; otherwise the old completion nils out the *new* gesture's snapshot reference, orphaning a view in the hierarchy.
- **`dismiss(animated: false)`** once your manual animation reaches the source frame. Calling `dismiss(animated: true)` would run the registered dismiss animator on top of your own animation — a second snapshot flies and the user sees two avatars.
- **`beginFromCurrentState`** in the animation options so a pan-during-animation handoff doesn't reset visible state.

### Fact 6: Gesture Coexistence with `UIScrollView.panGestureRecognizer`

`UIScrollView`'s built-in pan recognizer claims touch ownership for any pan starting inside the scroll view's bounds (= the entire screen). Without coordination, the dismiss pan never runs.

```swift
extension PreviewVC: UIGestureRecognizerDelegate {
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let pan = g as? UIPanGestureRecognizer, pan === dismissPan else { return true }
    guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001 else { return false }
    let v = pan.velocity(in: view)
    // Vertical-dominant only. Do NOT require v.y > 0 — the first sample of a
    // touch often reports (0, 0) or sub-pixel horizontal jitter, which puts
    // the recognizer in .failed for the entire touch sequence. Direction is
    // decided per-frame in handleDismissPan via max(0, translation.y).
    return abs(v.y) >= abs(v.x)
  }

  func gestureRecognizer(_ g: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    g === dismissPan
  }
}
```

Plus on the scroll view itself:

```swift
scrollView.bounces = false            // no rubber band → no contentOffset drift
scrollView.isScrollEnabled = false    // re-enable in scrollViewDidZoom when > min
scrollView.contentInsetAdjustmentBehavior = .never
```

`scrollViewDidZoom` flips `isScrollEnabled` on when `zoomScale > minimumZoomScale + 0.001` so the user can pan around a zoomed-in image, and back off at min zoom so the dismiss pan owns all touches.

### Fact 7: Third-Party VC With Self-Set `transitioningDelegate` Trap

Some libraries set `self.transitioningDelegate = self` in their `init` and provide a custom dismiss animator that **reparents the presenter view into the transition container**. This is safe when the presenter is `.fullScreen` (same size + container, no visual divergence) but breaks any other presentation style: after dismiss the presenter view never returns to its actual container, and the user sees a blank screen.

Confirmed example: [TOCropViewController#486](https://github.com/TimOliver/TOCropViewController/issues/486). The library's transition does:

```objc
[containerView insertSubview:previousController.view belowSubview:cropViewController.view];
```

If the presenter is `.formSheet`, the form sheet's view detaches from its container and never goes back — blank presenter after dismiss.

**Fix at the call site**:

```swift
let cropVC = CropViewController(croppingStyle: .circular, image: image)
cropVC.transitioningDelegate = nil   // ← strip library's self-set delegate
// UIKit now uses the standard modal animation, which is .formSheet-aware
present(cropVC, animated: true)
```

General rule: if a third-party VC takes over `transitioningDelegate` in its own init, audit what its dismiss animator does to the presenter view. If it reparents, set `transitioningDelegate = nil` and live with the standard modal animation.

### Fact 8: TOCropViewController Circular Crop → JPEG → White Corners

`croppingStyle: .circular` returns a `UIImage` with transparent corners (alpha channel). If your storage pipeline encodes as JPEG (no alpha), the corners become white. Subsequent display:

- In the source (`AvatarImageView` with circular mask) → corners clipped, no visible white.
- In a raw preview `UIImageView` → white corners visible against the blur.

Two options:

1. **Re-mask in the preview** with `cornerRadius + clipsToBounds` (Fact 3). Works with existing JPEG data. Chosen here.
2. **Store as PNG** to preserve alpha. Inflates file size for typical avatar content (~3–5× JPEG at equivalent quality). Reject unless transparency is required elsewhere.

## Anti-Pattern Table

| Pattern | Symptom | Fix |
|---|---|---|
| Set `frame` on a view with non-identity transform | `bounds` inflates by `1/scale`; downstream size math wrong; image renders at native pixels | Use `bounds.size =` |
| Manual `imageView.center = …` for centring | Centre resets to `(size/2, size/2)` on next `UIScrollView.layoutSubviews()` | Drive centring through `contentInset` + `contentOffset` |
| `modalPresentationStyle = .custom` with blur backdrop | Backdrop renders as flat grey panel | Use `.overFullScreen` so presenter stays in hierarchy |
| Asymmetric `contentInset(top, left, 0, 0)` for centring | Centres initially, drifts after pinch round-trip | Symmetric inset + `scrollViewDidEndZooming` offset snap |
| `UIPercentDrivenInteractiveTransition` for follow-finger pan | Linear scrub only; snapshot can be dragged off-screen | Manual gesture handler with snapshot |
| Pan gesture on `view`, no simultaneous-recognition delegate | `scrollView.panGestureRecognizer` wins; dismiss never fires | `shouldRecognizeSimultaneouslyWith` returns true |
| `velocity.y > 0` strict check in `shouldBegin` | First sample is `(0, 0)`; gesture stuck in `.failed` for whole touch | Check vertical-dominance only; decide direction in `.changed` |
| `dismiss(animated: true)` after manual pan animation | Double animation (yours + dismiss animator) | `dismiss(animated: false)` after own animation completes |
| `panSnapshot = nil` unconditionally in completion | Orphan snapshot when a new pan starts during cancel | `if self.panSnapshot === snapshot { … }` identity guard |
| Hide source via `isHidden = true` during hero | Stack-view layout invalidation jitters the source frame | `alpha = 0` (pure rendering toggle) |
| Convert source frame `to: window` | Misaligned under rotation / Stage Manager / safe-area | Convert `to: transitionContext.containerView` |
| Save circular crop output as JPEG | White corners in any unmasked display | Re-mask preview with `cornerRadius + clipsToBounds` |
| Third-party VC's self-set `transitioningDelegate` | Blank presenter after dismiss from `.formSheet` / non-fullscreen | Set `vc.transitioningDelegate = nil` before `present` |

## Diagnostic Workflow

When the preview is centred wrong / drifts / jumps:

1. `NSLog` the geometry on every `viewDidLayoutSubviews` and `scrollViewDidZoom`:
   ```swift
   NSLog("[Preview] scrollView.bounds=\(scrollView.bounds) " +
         "preview.frame=\(previewImageView.frame) " +
         "preview.bounds=\(previewImageView.bounds) " +
         "preview.center=\(previewImageView.center) " +
         "preview.transform=\(previewImageView.transform) " +
         "zoomScale=\(scrollView.zoomScale) " +
         "contentSize=\(scrollView.contentSize) " +
         "contentOffset=\(scrollView.contentOffset)")
   ```
2. `xcrun simctl spawn <udid> log show --last 1m --predicate 'process == "<App>"' --style compact | grep Preview` to read.
3. Look for `bounds.size` inflation (= `frame =` under transform) or `center` reset between two consecutive layout passes (= `UIScrollView` resetting zoom view origin).
4. **Do not guess** — read the actual numbers from the log first, then choose the fix above based on the trap signature. The same visual symptom (image off-centre) has at least three distinct root causes; only the log distinguishes them.
