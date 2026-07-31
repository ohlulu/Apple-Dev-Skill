# Agent Guidelines for Apple Dev Skill

This document provides guidance for AI agents working with this skill to ensure consistency and avoid common pitfalls.

## Core Principles

### 1. Apple App Development Focus
**This skill covers Apple platform app development.** It includes:
- UIKit patterns (and SwiftUI bridging where necessary)
- Xcode / Tuist project setup, xcconfig, build phases, Makefile
- Swift coding conventions scoped to app development

**Do not include:**
- Server-side Swift (Vapor, Hummingbird)
- Linux Swift or platform-agnostic CLI tools
- Backend patterns unrelated to Apple platforms
- Swift concurrency deep dives (use app-specific async patterns only)

### 2. No Architectural Opinions
**Stick to facts, not architectures.** Avoid:
- Enforcing MVVM, MVC, VIPER, or any specific architecture
- Mandating coordinator patterns
- Requiring specific folder structures beyond Xcode project layout
- Dictating dependency injection patterns

**Exception**: Suggest separating business logic for testability without enforcing how.

### 3. No Tool-Specific Instructions
**Agents cannot use external tools.** Do not include:
- Xcode Instruments profiling instructions
- Debugging tool usage
- IDE-specific features

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

## What to Include

### ✅ Include These Topics:
- View controller lifecycle
- Auto Layout (programmatic and Interface Builder)
- UITableView / UICollectionView patterns
- Diffable data sources and compositional layout
- Navigation patterns (push, present, custom transitions)
- Animation and transition APIs
- Performance patterns (cell reuse, image handling, off-screen rendering)
- UIKit-specific testing and testability patterns
- Accessibility best practices
- Modern UIKit APIs and deprecations
- Xcode project structure (Tuist, XcodeGen, pure Xcode)
- xcconfig hierarchy and build settings
- Build phase scripts and automation
- Makefile patterns for Xcode projects
- Swift type design, protocols, error handling for app code
- UIViewRepresentable bridging patterns

### ❌ Exclude These Topics:
- Swift concurrency deep dives (separate skill exists)
- Tool usage instructions
- Server-side Swift / Linux Swift
- SwiftUI deep dives (separate skill exists; bridging patterns are in scope)

## Updating the Skill

When adding new content:
1. Ask: "Is this relevant to Apple app development?"
2. Ask: "Is this a fact or an opinion?"
3. Ask: "Can agents actually use this?"
4. Ask: "Is this about correctness or style?"
5. Ask: "Which section of the Topic Router does this belong to?"

If unsure, err on the side of excluding content.

## Summary

**Focus**: UIKit/UI patterns, Xcode project setup, Swift app conventions
**Avoid**: Architecture enforcement, tools, server-side Swift
**Tone**: Factual, helpful, non-prescriptive
**Goal**: Make agents effective Apple app developers without enforcing opinions

## Linear

Tickets for this repo: label `skills` on team `OH`. `skills` covers all skill-authoring work — shared with `android-expert-skill` and the skills under `~/.pi` — so filter by title.

```bash
LINEAR_API_KEY="$(cat ~/.config/linear/api_key)" linear issue query --team OH --label skills
```
