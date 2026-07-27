# Keyboard Avoidance

## The Problem

UIKit does not automatically move content out of the keyboard's way. When a `UITextField` or `UITextView` near the bottom of the screen becomes first responder, the keyboard slides over it and the user cannot see what they are typing.

This applies to the system keyboard, `inputView` replacements (e.g., `UIDatePicker`), and any `inputAccessoryView`.

## Recommended Approach: Inset the Scroll View

The most reliable pattern is a single handler object that:

1. Observes `keyboardWillChangeFrameNotification` (one notification covers show, hide, resize, and iPad split/float).
2. Converts the keyboard's end frame into the scroll view's coordinate space.
3. Computes the overlap between the keyboard top and the scroll view bottom.
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

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        captureBaseline()
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handle(note) }
        }
    }

    private func captureBaseline() {
        guard let scrollView else { return }
        baselineContentInset = scrollView.contentInset
        baselineIndicatorInset = scrollView.verticalScrollIndicatorInsets
    }

    private func handle(_ note: Notification) {
        guard let scrollView,
              let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curve = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        let converted = scrollView.convert(endFrame, from: nil)
        let overlap = max(0, scrollView.bounds.maxY - converted.minY)

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
| Observing `willShow` + `willHide` separately | Misses resize events; race conditions on rapid focus changes |
| Hardcoding keyboard height | Varies by device, locale, input accessory, and predictive bar state |
| Forgetting to restore insets | Scroll view stays inset after keyboard hides |
| Applying overlap without checking baseline | Overwrites tab bar / safe area bottom inset |
| Background-tap dismisser that fires on control taps | `endEditing` relays out the screen before the control's `touchesEnded` arrives, so the control reports `.touchUpOutside` and the tap is silently swallowed |
