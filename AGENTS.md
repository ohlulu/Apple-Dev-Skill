# Agent Guidelines for Apple Dev Skill

## Core Principles

### 1. Apple App Development Focus
**This skill covers Apple platform app development.** It includes:
- UIKit patterns (and SwiftUI bridging where necessary)
- Xcode / Tuist project setup, xcconfig, build phases, Makefile
- Swift coding conventions scoped to app development

**Do not include** — each of these has its own skill or is out of scope entirely:
- Server-side Swift (Vapor, Hummingbird), Linux Swift, platform-agnostic CLI tools, backend patterns
- Swift concurrency deep dives → `swift-concurrency` skill; use app-specific async patterns only
- SwiftUI deep dives → `swiftui-expert-skill`; UIKit↔SwiftUI bridging stays here

The Topic Router in `apple-dev-skill/SKILL.md` is the authoritative list of what this skill actually covers. Do not maintain a second scope list anywhere — one drifted here for months, simultaneously omitting fourteen shipped references and naming three topics that were never written.

### 2. No Architectural Opinions
**Stick to facts, not architectures.** Avoid:
- Enforcing MVVM, MVC, VIPER, or any specific architecture
- Mandating coordinator patterns
- Requiring specific folder structures beyond Xcode project layout
- Dictating dependency injection patterns

**Exception**: Suggest separating business logic for testability without enforcing how.

### 3. No Tool-Driving Instructions
**Name a tool, never walk through driving it.** Simulator automation, UI verification, and macOS control each have their own skill (`axe`, `maestro`, `peekaboo`, `mcporter`), and duplicating their usage here guarantees two copies that drift.

GUI-only tools — Instruments, the Xcode view debugger, IDE inspectors — cannot be driven headlessly at all. Hand those to the user as a suggestion, the way SKILL.md does for the Core Animation profiler, rather than writing a walkthrough no agent can execute.

### 4. Chinese for Discussion, English for File Content
Use Chinese for all discussion, including deciding what skill content should say; use English only when writing or updating actual files.

## Content Guidelines

### Suggestions vs Requirements

**Use "suggest" or "consider" for optional optimizations:**
- ✅ "Consider prefetching cells for smoother scrolling"
- ❌ "Always prefetch cells"

**Use "always" or "never" only for correctness issues:**
- ✅ "Never force-unwrap IBOutlets in init"
- ✅ "Always call super in lifecycle methods"

### Examples

Examples are **not required by default**. Add them only when they reduce ambiguity or correct a common AI failure mode.

Use examples when a rule:
- Has a boundary (`use A here, B there`)
- Requires a specific output shape or ordering
- Is easy for agents to misread or overgeneralize
- Counters a common LLM habit

Skip examples for obvious, binary rules.

Keep examples minimal:
- Prefer 1 positive example
- Add 1 negative example only when contrast matters
- Example should clarify the rule, not restate it at length

A second code block that differs from the first only in type names or one property is not a second example — it is the first one paid for twice. Show the delta as a comment or a sentence instead.

### Say Each Rule Once

A rule lives in exactly one place: the section that carries its mechanism. Everywhere else points at that section.

Closing sections — `Checklist`, `Summary`, `Common Pitfalls`, `Warning Signs`, `Anti-Patterns` — may only hold items that appear nowhere else in the file, or that sequence body rules into an order the body does not impose (a pre-ship gate). Reformatting the body as a symptom lookup table is not new information; it is the same rule at double cost, and it drifts the moment one copy is edited.

The same applies within a file: a fact stated in an Overview, restated as a bullet, and restated again as a checklist item has been paid for three times. Keep the occurrence with the "why" attached and delete the others.

### Assume Baseline Competence

Do not restate what the model already produces correctly without being told: Apple's API Design Guidelines, the `Optional` / `throws` / `Result` / `precondition` severity ladder, protocol-oriented design, `.automaticDimension`, type-safe `dequeueReusableCell` wrappers, HIG's 44×44pt minimum.

The test is not "is this true?" but "would the output differ if this line were deleted?" Content that fails that test is rent paid on every load.

## Updating the Skill

When adding new content:
1. Ask: "Is this relevant to Apple app development?"
2. Ask: "Is this a fact or an opinion?"
3. Ask: "Can agents actually use this?"
4. Ask: "Is this about correctness or style?"
5. Ask: "Which section of the Topic Router does this belong to?"

If unsure, err on the side of excluding content.

## Linear

Tickets for this repo: label `skills` on team `OH`. `skills` covers all skill-authoring work — shared with `android-expert-skill` and the skills under `~/.pi` — so filter by title.

```bash
LINEAR_API_KEY="$(cat ~/.config/linear/api_key)" linear issue query --team OH --label skills
```
