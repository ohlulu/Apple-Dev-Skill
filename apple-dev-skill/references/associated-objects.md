# Eliminating objc_setAssociatedObject

## Core Principle

`objc_setAssociatedObject` attaches arbitrary data to an existing object at runtime via the ObjC runtime. In UIKit, it's most commonly used to retain handler/delegate objects or attach metadata to views. **It should be treated as a last resort** — every common use case has a pure Swift alternative that is type-safe, has predictable lifetime, and avoids ObjC runtime overhead.

## Why Avoid It

| Risk | Impact |
|------|--------|
| Actor classes: runtime abort | Swift runtime already bans associated objects on actor classes |
| Pure Swift classes: may be deprecated | Swift compiler engineers have signaled this direction (not yet formal) |
| `OBJC_ASSOCIATION_ASSIGN` is `unsafe_unretained` | Dangling pointer crash — not zeroing `weak` |
| `NONATOMIC` policy has race conditions | Concurrent read/write on same key can crash |
| Blocks optimizer reasoning about `deinit` | Runtime tracks association tables, forces slower deallocation path |
| Not cross-platform | No ObjC runtime on Linux/Windows |
| No type safety | Returns `Any?`, silent cast failures |

**Exception**: On `NSObject` subclasses in main-thread-only UIKit code, the practical risk is low. The motivation to eliminate is code quality, not crash prevention.

## The Three Common UIKit Use Cases

### 1. Handler/Target Lifetime — "Who holds the handler?"

**Symptom**: A factory/builder creates a handler object (target-action target, delegate, dataSource) but has no property to retain it. Without associated objects, ARC releases the handler immediately after the factory returns.

**Alternatives by priority**:

#### UIAction closure (iOS 14+) — eliminates the handler class entirely

For any `UIControl` subclass (`UITextField`, `UIDatePicker`, `UIButton`, `UISwitch`, `UISegmentedControl`, etc.):

```swift
// Before — handler class + associated object
let handler = ValueChangeHandler(index: index, onChange: callback)
textField.addTarget(handler, action: #selector(handler.valueChanged(_:)), for: .editingChanged)
objc_setAssociatedObject(textField, &key, handler, .OBJC_ASSOCIATION_RETAIN)

// After — no handler class needed
textField.addAction(UIAction { action in
    let tf = action.sender as? UITextField
    callback(index, tf?.text ?? "")
}, for: .editingChanged)
```

UIAction is retained by the UIControl. No external lifetime management needed.

**Scope**: Works for all `UIControl` events. Does NOT work for:
- `UIPickerView` (not a UIControl — requires delegate/dataSource objects)
- `UITextViewDelegate` (protocol-based, not event-based)
- `UIGestureRecognizer` (no UIAction init — use subclass approach below)

#### Subclass stored property — view owns its handler

When the handler must be a delegate/dataSource (UIPickerView, UITextView), store it on the view that uses it:

```swift
private final class FieldValueTextField: UITextField {
    /// Retains picker handler for the lifetime of this text field.
    var retainedHandler: AnyObject?
}

// Usage
let handler = FeetInchesPickerHandler(...)
picker.delegate = handler
picker.dataSource = handler
textField.retainedHandler = handler  // lives as long as textField
```

**⚠️ Delegate conflict pitfall**: If a subclass sets `self.delegate = self` to intercept events, any external `textField.delegate = viewController` will silently override it. **Rule**: subclass should use `addTarget(_:action:for:)` for its own reactions; leave `delegate` for external consumers.

### 2. Gesture Recognizer Target — "Who handles the tap?"

`UITapGestureRecognizer` does not support `UIAction`-based init. The target object must stay alive.

**Solution**: Make the view itself the target via a subclass:

```swift
private final class TappableRowView: UIView {
    private let tapAction: () -> Void

    init(content: UIView, action: @escaping () -> Void) {
        self.tapAction = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTap))
        )
    }

    @objc private func handleTap() { tapAction() }
}
```

The view IS the target — no separate wrapper object, no associated object.

### 3. Metadata Attachment — "I need to tag a view with data"

**Symptom**: Attaching domain data (IDs, indices, configuration) to a UIView that you don't own or can't subclass.

**Solution**: Wrapper view with stored property:

```swift
private final class FieldRowContainerView: UIView {
    var fieldDefIds: [Int64] = []
    let contentView: UIView

    init(content: UIView) {
        self.contentView = content
        super.init(frame: .zero)
        // same pin-to-edges init as TappableRowView above
    }
}
```

**⚠️ Wrapper identity trap**: After wrapping, `stackView.arrangedSubviews` contains the wrapper, not the content. Any `view is SomeType` check on arranged subviews must go through `(view as? WrapperView)?.contentView`. Audit ALL downstream code that:
- Checks `view is ConcreteType`
- Casts `view as? ConcreteType`
- Searches `arrangedSubviews.first(where:)`

This is the most common regression source when introducing view wrappers.

## Decision Table

| Situation | Solution | Eliminates |
|-----------|----------|------------|
| UIControl event handler | `addAction(UIAction { ... }, for:)` | Handler class + associated object |
| UIPickerView / UITextView delegate | Subclass stored property (`retainedHandler`) | Associated object |
| UIGestureRecognizer target | View subclass as target | Wrapper class + associated object |
| Data attached to arbitrary view | Wrapper view with stored property | Associated object + unsafe key |
| Short-lived session objects (OAuth) | Caller holds instance (class, not struct) | Associated object on VC |

## Short-Lived Session Objects

When retaining objects for the duration of an async flow (e.g., OAuth session + presentation anchor), do NOT use associated objects on the presenting VC or static properties on a type.

**Use a class instance held by the caller's async frame:**

```swift
@MainActor
final class OAuthSession {
    private var anchor: Anchor?
    private var session: ASWebAuthenticationSession?

    func authenticate(...) async throws -> URL {
        // self.anchor = ..., self.session = ...
        // Instance lives as long as the caller's await
    }
}

// Caller — instance retained in async frame
func startAuth() async throws {
    let oauth = OAuthSession()
    let url = try await oauth.authenticate(...)
    // oauth released when startAuth returns
}
```

Swift async frames retain local variables until the function returns — the instance stays alive during `await` without any external storage.

**Why not static properties?** Global state. Concurrent calls overwrite. Semantic mismatch — session lifetime should bind to the flow, not the type.
