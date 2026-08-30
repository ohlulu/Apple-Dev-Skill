# Modular Architecture (iOS)

How to modularize an app: the target blueprint, a placement procedure for new
code, standard recipes for shared logic and screen reuse, monolith migration
steps, the module physical form, and the linkage decision.

## When to Apply / Not for

Apply when: designing module layout, deciding where new code lives, extracting
features or services, asked to "split into modules", fixing
modularization-induced build pain, or choosing library linkage.

**Gate first**: solo project or small app with no build pain → **recommend
staying single-module**. Modularize only on team growth or concrete symptoms
from the anti-pattern table below. Splitting without pain creates overhead,
not architecture.

NOT for server-side Swift or standalone SPM library design — app-project
scoped.

## Target Blueprint (default to this; don't reinvent)

```
App → Features → Workflows → Services → Core
```

| Layer | Contains | May import |
|---|---|---|
| App | scene setup, deep links, DI wiring | everything |
| Features | screens + flows; each feature ships a thin API module | other features' **APIs** (never implementations), Workflows, Services |
| Workflows | multi-service orchestration ("generate summary", "sync data") | Services, Core |
| Services | one domain responsibility per module | Core only — **never sibling services** |
| Core | dependency-free generic utilities | nothing |

Two iron rules; violating either is an architecture error:

1. **Same-layer modules never import each other** (feature implementations,
   services, Core utilities). A flow that spans same-layer peers moves one
   layer up.
2. **Wire everything with constructor injection at the App root.** This makes
   the layering compiler-enforced — a dependency cycle simply doesn't compile.
   No DI framework.

## Placement Procedure (run for every new type or module)

Answer in order; the first hit is the answer:

1. A screen or user flow? → **Features** (and check whether its API module
   grows with it)
2. Coordinates two or more services? → **Workflows**
3. Business logic with a single domain responsibility? → **Services**, its
   own module
4. Domain-free utility with zero dependencies? → **Core**

**No instant hit on any of the four → stop.** The layer taxonomy is missing
something; re-examine the blueprint instead of shoehorning into the nearest
layer — a shoehorned type is the seed of the next grab-bag module.

## Recipe: Two Features Need the Same Business Logic

**Never**: copy the logic; have feature A import feature B; drop it into a
"Shared" / "Common" grab-bag module.

**Do**:

1. Extract the logic into its own Services-layer module (one responsibility =
   one module).
2. Both features import that service.
3. If the "shared" thing is actually a flow across several services → extract
   a Workflow module; features import the workflow.

Why: logic living inside a feature forces an awkward refactor the moment a
second feature needs it; logic in a grab-bag module grows into a god module
everything imports. One-responsibility-one-module removes both paths.

## Recipe: Feature A Must Present Feature B's Screen

**Never**: import B's implementation from A; invent a low-level shim protocol
plus `AnyView` wrapping for one call site — that bypasses the boundary
instead of building one.

**Do**:

1. Define (or extend) a screen factory protocol in B's API module:

   ```swift
   // FeatureBAPI module — the entire module is roughly this
   public protocol FeatureBScreenFactory {
       func makeSomeScreen() -> UIViewController
   }
   ```

2. Implement it in B's implementation module.
3. Inject the concrete factory during App-layer DI wiring.
4. A imports only `FeatureBAPI` and obtains the screen through the factory.

Side benefit: dependents see only the API module, so as long as the public
interface is unchanged, B's internal changes don't recompile A — the
pattern's mechanical build-time payoff.

**Prerequisite check**: this requires (a) constructor injection and (b) a
navigation architecture that can host externally-created screens. Missing
either → build the prerequisite first; don't force the pattern.

## Recipe: Migrate a Monolith to the Blueprint

In order; don't skip:

1. **Prerequisites first**: DI, navigation rework, one screen factory per
   feature (they later graduate into API modules).
2. **Extract leaf-first**: dependency-free utilities into Core, then upward
   layer by layer (Services → Workflows → Features). Never start from the
   top.
3. **One module (or one layer) per pass, one PR per pass**, verified by a
   build each time. Import churn is mechanical — delegable to agents.
4. **Timing**: finish *before* growing the team — nobody should learn the
   architecture twice.

## Anti-Pattern Recognition

| Anti-pattern | Symptom | Fix |
|---|---|---|
| Service stranded in the app target | lower layers reach it only via awkward dependency inversion | extract into a Services module |
| Sibling services importing each other | changing one service ripples into another | lift the cross-service flow into a Workflow |
| Hyper-modular tax | 5–8 targets per feature; single-screen features pay full price | add targets only when previews / example apps / swappable impls are actually needed |
| Deep chains & hub modules | builds can't parallelize; one edit recompiles the graph | keep the graph wide and shallow; fence invalidation behind stable interfaces |
| Tests forcing `private` → `internal` | a single module can't enforce encapsulation at boundaries | module boundaries make `public` meaningful again |

## Module Physical Form

Pick by project type; the first match decides — don't mix forms casually:

1. **Generated project (Tuist / XcodeGen) → one module = one Project.**
   Multiple targets inside a project carry only *facets of the same module*:
   API + implementation (the feature-contract case), tests, testing/mocks,
   an example app, platform variants (CoreKit / CoreKitiOS), resources.
   The test: **targets are compiler boundaries; projects are ownership
   boundaries.** Two compilation units with one responsibility, one owner,
   changing in lockstep → same project, separate targets. A new
   responsibility → a new project. Add facet targets on demand, never
   ceremonially (see the hyper-modular tax row above). Dependents import
   targets, not projects: other features depend only on the API target;
   only the App layer touches the impl target during DI wiring. Wire with
   cross-project references (see xcode-project-setup.md §3; its
   when-to-add-a-project table complements this rule).
2. **Plain Xcode project, no generator → local SPM packages.**
   `Package.swift` is declarative and merge-friendly; hand-editing pbxproj
   to add framework targets reinvites the conflicts a generator would have
   killed. Prefer one package with multiple targets (the graph stays in one
   manifest); split into separate packages only when release cadence
   differs.
3. **Framework targets in a hand-maintained xcodeproj**: only when a module
   needs what SPM can't express (custom build phases, per-module xcconfig,
   mergeable libraries, resource-heavy targets) and no generator is in
   play.

Before choosing SPM, confirm these limits don't block you: coarse
build-settings control (no xcconfig), SwiftUI previews notoriously flaky
inside packages, and the only linkage knob is marking a product `.dynamic` —
mergeable is a framework-target feature.

API contract modules are cheap in every form — an SPM target or framework
target holding one protocol file. Never skip the contract because "another
module feels heavy".

Tooling notes: don't start new projects on CocoaPods / Carthage; touch
Buck / Bazel only if you accept maintaining that complexity forever.
tuist-spm-integration.md covers third-party SPM dependencies in Tuist
projects.

## Linkage Decision

1. **Default static**: fast launch (one Mach-O), dead-code stripping applies.
2. **Go dynamic only when** multiple targets (app + extensions) share one
   copy *and* a profile confirms the saving. Two facts to hold: dynamic
   frameworks are mapped wholesale in pre-main (not on demand), so each one
   costs launch time; and dynamic skips dead-code stripping, so it can be
   *bigger* than the static equivalent (observed: the same small dependency
   at 200 kB dynamic vs 15 kB static).
3. **Prefer mergeable on Xcode 15+**: dynamic in Debug for iteration speed,
   merged in Release for launch speed.
4. Verify any change with the App Launch instrument; never apply the
   "dynamic-shared-saves-space" dogma unprofiled.
