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
