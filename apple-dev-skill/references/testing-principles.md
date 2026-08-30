# Testing Principles

## Overview

General testing principles that apply to UIKit integration tests. For UIKit-specific lifecycle simulation, interaction helpers, and screen testing patterns, see [testing.md](testing.md).

## Test Levels

1. **Composition / wiring tests** — verify app wiring and navigation setup (window visible, root VC correct, push/present wiring).
2. **Feature integration tests** — the default for UIKit screens. Real views + loader spies/stubs. Assert rendered UI state.
3. **Acceptance tests** — small number of end-to-end tests with real collaborators. Keep narrow and high-value.

## Async Testing

Do not rely on sleeps or arbitrary delays.

Use async spies that:
- record requests
- let the test complete/fail each request explicitly
- report whether a request completed, failed, or was cancelled

This makes UI tests deterministic and lets you verify cancellation rules.

## Assertion Strategy

- visible title, labels, images
- loading/error indicator visibility
- row count, button state

## Memory Leak Tracking

Track the screen under test and long-lived collaborators for leaks.

```swift
extension XCTestCase {
    func trackForMemoryLeaks(_ instance: AnyObject, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance, "Instance should have been deallocated.", file: file, line: line)
        }
    }
}
```

Use for:
- the view controller under test
- loader spies/stubs retained by the screen
- adapters/presenters that should deallocate with the screen
