# Keyboard Avoidance

## The Problem

UIKit does not automatically move content out of the keyboard's way. When a `UITextField` or `UITextView` near the bottom of the screen becomes first responder, the keyboard slides over it and the user cannot see what they are typing.

This applies to the system keyboard, `inputView` replacements (e.g., `UIDatePicker`), and any `inputAccessoryView`.

## Recommended Approach: Inset the Scroll View

The most reliable pattern is a single handler object that:

1. Observes `keyboardWillChangeFrameNotification` (one notification covers show, hide, resize, and iPad split/float) and `keyboardDidChangeFrameNotification` (re-measures after the host view may have moved — see [Re-measure on `didChangeFrame`](#re-measure-on-didchangeframe)).
2. Converts the keyboard's end frame into the scroll view's coordinate space.
3. Computes the overlap from the intersection of the keyboard frame and the scroll view bounds — not from `bounds.maxY - keyboard.minY` (see [Overlap Is an Intersection](#overlap-is-an-intersection-not-a-subtraction)).
4. Adjusts `contentInset.bottom` and `verticalScrollIndicatorInsets.bottom` to match.
5. Scrolls the first responder into view.
6. Restores original insets when the keyboard hides.

### Skeleton

```swift
@MainActor
final class KeyboardScrollHandler {
    private weak var scrollView: UIScrollView?
    private var baselineContentInset: UIEdgeInsets = .zero
    private var baselineIndicatorInset: UIEdgeInsets = .zero
    private var keyboardEndFrame: CGRect = .zero
    private var currentOverlap: CGFloat = 0

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        captureBaseline()
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handle(note, settled: false) }
        }
        nc.addObserver(
            forName: UIResponder.keyboardDidChangeFrameNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handle(note, settled: true) }
        }
    }

    private func captureBaseline() {
        guard let scrollView else { return }
        baselineContentInset = scrollView.contentInset
        baselineIndicatorInset = scrollView.verticalScrollIndicatorInsets
    }

    private func handle(_ note: Notification, settled: Bool) {
        guard let scrollView,
              let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curve = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        keyboardEndFrame = endFrame
        let converted = scrollView.convert(endFrame, from: nil)
        let overlap = Self.bottomOverlap(keyboardFrame: converted, in: scrollView.bounds)

        // The settled pass only acts when the host view moved under the keyboard.
        if settled, abs(overlap - currentOverlap) <= 0.5 { return }
        currentOverlap = overlap

        var options = UIView.AnimationOptions(rawValue: curve << 16)
        options.formUnion(.beginFromCurrentState)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            var content = self.baselineContentInset
            content.bottom = max(self.baselineContentInset.bottom, overlap)
            scrollView.contentInset = content

            var indicator = self.baselineIndicatorInset
            indicator.bottom = max(self.baselineIndicatorInset.bottom, overlap)
            scrollView.verticalScrollIndicatorInsets = indicator
        }

        // Scroll active field into view
        if overlap > 0, let responder = scrollView.findFirstResponder() {
            let rect = responder.convert(responder.bounds, to: scrollView)
            scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -16), animated: true)
        }
    }

    static func bottomOverlap(keyboardFrame: CGRect, in scrollBounds: CGRect) -> CGFloat {
        let intersection = scrollBounds.intersection(keyboardFrame)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        guard intersection.maxY >= scrollBounds.maxY - 0.5 else { return 0 }
        return scrollBounds.maxY - intersection.minY
    }
}
```

### Usage

Store the handler as a property so it stays alive for the screen's lifetime:

```swift
final class EditViewController: UIViewController {
    private lazy var keyboardHandler = KeyboardScrollHandler(scrollView: scrollView)

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = keyboardHandler // activate
    }
}
```

## Key Details

### Why `keyboardWillChangeFrameNotification`?

A single notification handles all transitions: show, hide, dock/undock, resize (iPad split keyboard, predictive bar changes). No need to observe `willShow` and `willHide` separately.

### Re-measure on `didChangeFrame`

Always observe `keyboardDidChangeFrameNotification` too and re-run the same measurement from it. A presentation controller may relocate the host view inside the same keyboard animation — an iPad form sheet is pushed up so the keyboard does not cover it — and at `willChangeFrame` time the scroll view still sits at its pre-move position. The overlap computed there is against geometry that no longer exists once the animation lands (observed: 212pt computed, 39pt real). Nothing else re-measures, so the inset and the responder scroll stay wrong until the keyboard hides.

The settled pass re-measures with the stored end frame and only re-applies when the result differs from the pending overlap by more than a sub-pixel tolerance. Full-screen scroll views never move, so for them it is a no-op; the extra observer costs nothing where it is not needed.

### Overlap Is an Intersection, Not a Subtraction

`bounds.maxY - keyboard.minY` is correct only for a docked keyboard that spans the scroll view's width. iPad's floating keyboard breaks it two ways:

- Parked beside the sheet with no horizontal overlap — the end frame's `minY` is still below the sheet's bottom, so the subtraction reports a phantom inset. `CGRect.intersection` is null, and the handler exits with 0.
- Dragged up so it hovers above the scroll view's lower edge — the rects intersect, but the keyboard is not trapping content against the bottom. Count the intersection as an intrusion only when it reaches the scroll view's `maxY`; otherwise `scrollRectToVisible` alone keeps the field visible.

Keep the function static and pure so it can be unit-tested with plain rects.

### Animation Curve

The keyboard uses a private animation curve (value `7`). Extracting the raw value from the notification and shifting it into `UIView.AnimationOptions` produces a synchronized animation that matches the keyboard slide exactly.

### Baseline Insets

Capture the scroll view's original `contentInset` and `verticalScrollIndicatorInsets` before the first keyboard event. Always add overlap on top of the baseline — never overwrite the original bottom inset, which may account for a tab bar or safe area.

### `scrollRectToVisible` Padding

Inset the target rect by a negative amount (e.g., `-16pt`) so the field has breathing room above the keyboard, not pinned to the edge.

### `inputView` Counts as Keyboard

When a text field uses a custom `inputView` (e.g., `UIDatePicker` as `.wheels`), the system treats it as a keyboard. The same `keyboardWillChangeFrame` notification fires, with the input view's frame as the end frame. No special handling is needed.

## Background-Tap Dismissers Must Ignore Controls

A root-view `UITapGestureRecognizer` that calls `endEditing(true)` is the standard "tap blank space to dismiss the keyboard" affordance. Two guards are required, and the second one is the non-obvious one:

1. `cancelsTouchesInView = false`, or the gesture eats the touch and every button and row underneath stops responding.
2. Refuse touches that land on a `UIControl` — implement `gestureRecognizer(_:shouldReceive:)` and walk `touch.view`'s superview chain, returning `false` as soon as a `UIControl` appears.

```swift
func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
  var candidate = touch.view
  while let current = candidate {
    if current is UIControl { return false }
    candidate = current.superview
  }
  return true
}
```

Why guard 2 is mandatory on any keyboard-avoiding screen: the gesture's action runs BEFORE the delayed `touchesEnded` reaches the control. `endEditing(true)` triggers a keyboard-hide layout pass, and a layout pass writes the final frame to the **model** layer immediately (only the presentation layer animates). `UIControl.endTracking` then tests the touch-up point against the control's NEW frame, sends `.touchUpOutside`, and the action never fires. Symptom: the keyboard drops, nothing else happens, the user taps the same button twice. The bigger the keyboard-driven shift, the more reliably the first tap is lost.

`cancelsTouchesInView = false` does not help here — it keeps the touch flowing but cannot stop a layout change landing mid-delivery.

Deferring the dismissal (`DispatchQueue.main.async { endEditing(true) }`) also masks it, but it couples correctness to run-loop ordering and cannot be unit-tested. Prefer the semantic rule: a control tap is not a blank-area tap. Extract the predicate as a static function so it is testable without synthesizing a `UITouch`.

Downstream consequence to state in the helper's doc comment: a `UIControl` tap no longer dismisses the keyboard as a side effect. A control that needs the keyboard gone calls `endEditing` in its own action.

## Anti-Patterns

| Pattern | Problem |
|---------|---------|
| Adjusting the view's frame or transform | Breaks Auto Layout; doesn't survive rotation |
| Hardcoding keyboard height | Varies by device, locale, input accessory, and predictive bar state |
| Measuring only in `willChangeFrame` | Form sheets move during the animation; see [Re-measure on `didChangeFrame`](#re-measure-on-didchangeframe) |
| `bounds.maxY - keyboard.minY` as the overlap | Phantom inset for a floating keyboard; see [Overlap Is an Intersection](#overlap-is-an-intersection-not-a-subtraction) |
| Forgetting to restore insets | Scroll view stays inset after keyboard hides |
| Background-tap dismisser that fires on control taps | See [Background-Tap Dismissers Must Ignore Controls](#background-tap-dismissers-must-ignore-controls) above |
