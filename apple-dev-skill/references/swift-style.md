---

# Swift Coding Style

Conventions and traps specific to this codebase. Baseline Swift practice — Apple's API Design Guidelines, protocol-oriented design, the `Optional` / `throws` / `Result` / `precondition` severity ladder — is assumed, not restated here.

## Type Design

### Immutability First
Default to `let` and `struct`. Mutability requires justification.
When modification is needed, create a new value — don't mutate in place.
Derive display data via computed properties; never store what you can compute.

**Struct memberwise init trap:** `let` properties with default values are
*excluded* from the synthesized memberwise init — the default becomes a
compile-time constant that callers cannot override. Use `var` with a default
when a property should be optional at the call site but immutable in spirit.
Class properties are unaffected (no synthesized memberwise init).

### Model Variants as Sum Types
If two fields can contradict each other, the model is wrong. A boolean plus an
optional encodes states that cannot occur; an enum with associated values makes
them unrepresentable, so the compiler flags every unhandled case when a variant
is added later.

### Appearance Variants as Configuration

A view that looks slightly different in different places is a configuration
problem, not a sum type. An `enum Style` whose cases differ only in colors,
fonts, or spacing scatters each value across `style == .x ? a : b` branches:
reading one variant means reading every branch, and adding a variant means
revisiting every switch. Choose the form by how widely the configuration is
reused, not by how many values differ:

- **Reused across many call sites, or named by the design system** (the
  guideline's primary / secondary button, its text styles): a `struct` of the
  varying values plus named `static` presets, the way `UIButton.Configuration`
  offers `.filled()` and `.plain()`. The preset is the single point of change
  when the design system revises the style, so name it with the design
  system's term, never after the screen that uses it. A variant is written as
  the preset it starts from plus the values it changes.
- **Local to one or two call sites**: the component exposes only the subviews
  whose appearance varies — everything else stays private — and each call site
  sets them in its factory method. A preset here only adds a hop between the
  call site and its values, however many values differ.
- **Cases whose layout or data actually differ** (`.top(inset:)` vs `.center`
  produce different constraints): keep the enum — exhaustive switching is
  doing real work, as in Model Variants as Sum Types.

```swift
final class RankEntryView: UIView {
    let nicknameLabel = UILabel()   // exposed: varies per call site
    let countLabel = UILabel()

    private let avatarView = UIImageView()  // identical everywhere: stays private
}

// Call site owns its variant
private lazy var entryView = makeEntryView()

private func makeEntryView() -> RankEntryView {
    let view = RankEntryView()
    view.nicknameLabel.textColor = .secondaryLabel
    return view
}
```

Existing `enum Style` types count as a project convention (see the Precedence
Rule in SKILL.md) only when the project's written style guide prescribes them;
otherwise they are legacy, and new code takes the form above.

### Phantom Types

Type parameters declared on a generic but never used in stored properties,
providing extra type information purely at compile time.

- Use caseless enums as phantom markers (they can't be instantiated)
- Use when the same underlying data appears in multiple semantic contexts and
  mixing them would be a logic error
- Constrained extensions can make specific methods available only for specific
  variants

### Typed Throws

`throws(SomeError)` allows exhaustive switching in catch blocks, but untyped
throws is the better default: a typed throw is a source-breaking change the
moment a new failure mode appears. Reserve it for internal module code and
generic pass-through functions, where the error set is already closed.

---

## File Organization

### Private Members
- Private members go at the **end** of the file in a separate `extension`, not
  inside the main type body
- Exception: very small files (single short type) — private helpers may stay
  inside the type body at the bottom; no extension needed

### MARK Comments
- **UIKit subclasses** (view controllers, views, cells) → use the MARK
  anchors from [file-structure](file-structure.md): `// MARK: - Lifecycle`
  in the type body, `// MARK: - <Responsibility>` on each extension.
  These files run long; MARK anchors let offset-based file reads land on
  the right section.
- **Plain Swift types** (models, services, small value types) → skip MARK
  inside the type body; grouped members are self-evident at that size.
  On `extension` blocks, add a MARK only when the extension's purpose
  isn't obvious at a glance.

### Error Type Placement
- Nest error types inside the concrete implementation as `Error`
  (e.g., `FileManagerImageStorageService.Error`), not as standalone top-level
  enums
- Protocols declare `throws` only; errors belong to the concrete type by default
- When a protocol needs typed throws for a specific reason, the error type may
  live at the protocol level — but treat this as the exception, not the rule

---

## Comments

### Load-Bearing Lines
A line whose removal still compiles and passes the tests but breaks runtime
behavior — a forced view load, a layout flush, a statement-order dependency, a
re-entrancy guard — carries a comment stating what breaks without it, not what
it does:

```swift
// Load-bearing: forces the view to load so the transition queue can drain;
// without it, off-screen instances never report ready.
_ = self.view
```

Never delete a line marked load-bearing as redundant without first
reproducing the failure it guards against.
