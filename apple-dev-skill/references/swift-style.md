---

# Swift Coding Style

## Opaque vs Existential Types

- **Default to `some`** — static dispatch, full associated type access, compiler
  optimizations
- **Use `any` only when heterogeneous storage is needed** — dynamic dispatch,
  runtime overhead
- Primary associated types (`any Loadable<User>`) greatly reduce the need for
  manual type-erasing wrappers

## Exhaustive Switch

- Prefer listing all cases explicitly over using `default`
- Adding a case makes the compiler flag every unhandled switch — "follow the
  compiler errors to refactor"
- Use `@unknown default` for non-frozen enums as a forward-compatibility safety
  net

## Phantom Types

Type parameters declared on a generic but never used in stored properties,
providing extra type information purely at compile time.

- Use caseless enums as phantom markers (they can't be instantiated)
- Use when the same underlying data appears in multiple semantic contexts and
  mixing them would be a logic error
- Constrained extensions can make specific methods available only for specific
  variants

## Newtype / Tagged Types

Wrap primitive types in a single-property struct to eliminate primitive obsession.

- `typealias` is just a synonym — it provides zero additional safety
- Newtype initializers can enforce invariants (e.g., `EmailAddress` validates
  format at construction)
- Conditional conformance lets wrapper types automatically inherit applicable
  protocol conformances from the underlying value

## Typed Throws

- `throws(SomeError)` allows exhaustive switching in catch blocks
- But **untyped throws is the better default in most scenarios**
- Typed throws is best suited for internal module code and generic pass-through
  functions

---

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

### Let the Type System Enforce Correctness
- **Eliminate illegal states** — If two fields can contradict each other,
  the model is wrong. Use enums with associated values instead of boolean +
  optional pairs.
- **Prefer sum types for variants** — Struct is a product type (AND); enum
  with associated values is a sum type (OR). Choose the right algebraic
  combination to model your domain precisely.
- **Never store derived data** — If a value can be computed from another
  field, make it a computed property. Redundant storage drifts.
- **Group what belongs together** — Fields that are only meaningful as a unit
  should live in one type. Scattered fields invite partial updates.
- **Express impossibility in types** — `Never` as a generic parameter
  (e.g., `Result<Data, Never>`) communicates at the type level that a case
  cannot occur. Turn "should never happen" runtime guards into type constraints.

---

## Protocol-Oriented Programming

- Start with protocols, not classes
- Protocols define capabilities ("acts as") rather than identity ("is a")
- **But don't over-protocol** — explore with concrete types first, then abstract
  once you understand
- Consider composing existing protocols before creating new ones
- Rule of Three: extract into a reusable component only when a pattern appears
  three times

## Composition over Inheritance

- Structs can't inherit from each other; Swift supports only single class
  inheritance — the type system actively favors composition
- Protocol extensions serve as mixins/traits — types can adopt multiple protocols
  to gain behavior
- **Default to struct + protocol; use class inheritance only when the framework
  requires it** (UIKit, SwiftData)

---

## Error Handling

Swift provides layered error handling strategies — choose by severity:

- **Optional** — absence is a normal, expected outcome
- **throws / try** — failure is expected but exceptional (network, file I/O)
- **Result** — errors need to be stored, passed around, or composed
- **assert()** — debug-only internal consistency checks
- **precondition()** — public API contract violations (still active in release builds)
- **fatalError()** — truly unrecoverable states

### Defensive Programming Judgment
- **Logic errors** (bugs in your code) → crash (assert / precondition / fatalError)
- **Runtime failures** (network down, invalid input) → recover gracefully
  (Optional / Result / throws)
- In production, reserve `fatalError` for conditions that should never occur in
  a correctly shipped app

---

## API Design

Follow Apple's official API Design Guidelines:

- **Clarity at the point of use is the most important goal** — more important
  than brevity
- Name mutating methods as imperative verbs (`x.sort()`); non-mutating as noun
  phrases (`x.sorted()`)
- `-ed` / `-ing` suffixes denote non-mutating variants
- Boolean properties should read as assertions (`isEmpty`, `intersects`)
- Name parameters by role (`greeting`), not type (`string`)
- Omit needless words that repeat type information

### Progressive Disclosure
- Simple tasks should require only simple code
- Provide sensible defaults; allow progressive customization
- Design for common cases first; add customization points for advanced use

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

## Generation Checklist

Before shipping new Swift types:

- [ ] `let` + `struct` by default; every `var` / `class` has a reason
- [ ] No boolean + optional pairs that can contradict — model variants as enums with associated values
- [ ] No stored derived data — computed properties instead
- [ ] Error severity matches the mechanism (Optional / throws / Result vs assert / precondition / fatalError)
- [ ] Names follow Apple API Design Guidelines (mutating imperative, non-mutating noun/-ed/-ing, boolean assertions)
- [ ] Private members in a trailing `private extension` (except very small files)
- [ ] Error types nested inside the concrete implementation, not top-level
- [ ] MARK usage matches the file kind (UIKit subclass → file-structure anchors; plain type → minimal)
