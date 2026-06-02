# Implicit Animations — Catalog & Suppression

UIKit and Core Animation fire animations *without* a `UIView.animate`
block: setting a layer property mid-runloop schedules a CABasicAnimation
under the hood, certain UIKit controls re-animate state on assignment,
and some animations are tied to layout passes that the app didn't ask
for. These are easy to miss when reviewing code (no `animate { }` to grep
for) and easy to chase when debugging (each one looks like a *separate*
animation; many are intermediate frames of the same layout resolve).

This reference is the catalog, the disable-at-the-source recipes, and
the iOS version notes for behavior changes.

## When Implicit Animations Help

- **State change feels like a transition** — toggling a `UISwitch`
  programmatically as a confirmation of user intent (e.g. "you turned
  this on") should still animate so the affordance reads.
- **Diff visualization** — `UITableViewDiffableDataSource.apply` with
  `animatingDifferences: true` makes an add/delete/move legible.
- **Trial → Active subscription** — a *deliberate* state transition
  earned by a user action.

## When They Hurt

- **Content surfaces re-rendering loaded state** — Settings detail
  panes, dashboard tiles, status banners. The user picked a section;
  they expect the new content, not a transition.
- **First paint** — anything that paints from empty → loaded reads as
  noise, not as a state change.
- **Layout pass against `.zero`** — the iOS 26 master-detail
  regression (see `split-view-controller.md`) makes every sub-element
  appear to animate as Auto Layout resolves the new VC's view from
  `.zero` to real bounds inside the transition window. See
  **Sub-Layer Resolution Artifacts** below.

## Catalog: What Animates and Why

### `CAGradientLayer.colors` — iOS 7+

Default action `"colors"` runs a CABasicAnimation crossfade
(~0.25s). Triggers on every assignment, even on first paint when
going from `nil` (initial state) to a value.

```swift
// Implicit crossfade every time
gradientLayer.colors = [accent500.cgColor, accent700.cgColor]
```

**Disable at the source**:

```swift
gradientLayer.actions = ["colors": NSNull()]
```

Set once in the layer's owning view's `init`. Permanently disables the
implicit crossfade; explicit `UIView.animate` or `CATransaction` blocks
around the property write are still respected.

### `CALayer.bounds` / `position` — pre-1.0

Standard layer actions. `bounds` animates whenever the layer's frame
changes outside an explicit `UIView.animate` block, e.g. during a layout
pass triggered by `intrinsicContentSize` propagating up.

```swift
gradientLayer.actions = [
  "colors": NSNull(),
  "bounds": NSNull(),
  "position": NSNull(),
]
```

This is the standard "this layer never animates" recipe for a layer that
just decorates a UIView and follows its `bounds`.

### `UISegmentedControl.selectedSegmentIndex` — iOS 13+

Setter animates the selector pill from current to new index when the
delta is non-zero. The 0 → 0 (no-op) does not animate.

The "weird animation on the segment when the detail VC mounts" you've
seen is almost certainly **not** this — it's the Auto Layout resolve
during the iOS 26 transition window (see `split-view-controller.md`).
The pill is positioning relative to the segment's intermediate bounds,
which read as motion. Once the layout fix is in place the pill is
already at its final position when the first frame paints.

**Sync without animation**:

```swift
segmented.selectedSegmentIndex = draft.capType.rawValue
// no `setSelectedSegmentIndex(_:animated:)` overload — the setter
// animates by default and the only way to suppress per-call is
// CATransaction. Prefer fixing the root layout cause.
```

### `UISwitch.setOn(_:animated:)` — iOS 6+

Convenience setter `isOn` calls `setOn(_:animated: true)` under the
hood for *some* paths. Initial sync from a draft should pass
`animated: false` explicitly:

```swift
// Animates thumb
toggle.isOn = draft.welcomeEnabled

// Doesn't
toggle.setOn(draft.welcomeEnabled, animated: false)
```

### `UILabel.text` — does NOT animate

Despite occasional appearances. If you see a label "fade in" during a
transition, the cause is one of:

- The label's *layer* is being added to a parent layer that's animating
  (size, opacity)
- The label's frame is animating because its `intrinsicContentSize`
  is propagating through a layout pass that's animating
- The whole VC view tree is mid-Auto-Layout-resolve (the iOS 26
  regression)

Fix the parent / layout, not the label.

### `UIImageView.image` — does NOT animate

Unless `animationImages` / `animationDuration` are configured, image
assignments are instant.

### Cell insert / delete in diffable data source — pre-existing

`UITableViewDiffableDataSource.apply(_:animatingDifferences:)` and
`UICollectionViewDiffableDataSource.apply(_:animatingDifferences:)`
animate every diff when `animatingDifferences: true`. The catch:
**a first-paint apply against an empty data source counts every row as
an insertion**. So on detail VC mount + first apply, the rows slide /
fade in even though to the user it's just "show me the section".

See `list-composition.md` → "First-Apply Animation Gate" for the
correct gate pattern.

## Bind-Before-Load: The Sync-Fire Trap

**This is the bug that looks like iOS 26 `.zero`-frame settling but
isn't.** The two share a symptom ("content expands from origin during
appearance"), live in the same neighborhood of the codebase
(detail-VC `viewDidLoad`), and respond identically to surface
observation. Both share the same underlying mechanism — `UIView
.animate` capturing a `.zero` state — but the *trigger* is different,
and the fix is different.

### The trap

```swift
override func viewDidLoad() {
  super.viewDidLoad()
  setupUI()
  bindViewModel()          // ← registers viewModel.onChange = { ... }
  viewModel.loadSettings() // ← SYNCHRONOUS mutate; fires onChange
  syncFieldsFromDraft()
  refreshDirtyState(animated: false)
}

func bindViewModel() {
  viewModel.onChange = { [weak self] in
    self?.syncFieldsFromDraft()
    self?.refreshDirtyState(animated: true)   // ← the time bomb
  }
}

func refreshDirtyState(animated: Bool) {
  saveBar.setDirty(viewModel.isDirty, animated: animated)
  // saveBar.setDirty wraps the state change in UIView.animate(...) {}
}
```

**Step-by-step**:

1. `bindViewModel()` registers `viewModel.onChange = { ... refreshDirtyState(animated: true) }`.
2. `viewModel.loadSettings()` is *synchronous*. It mutates the draft
   and fires `onChange` **before returning**.
3. The bound callback runs inside `viewDidLoad`. `view.frame` is still
   `.zero`.
4. `refreshDirtyState(animated: true)` triggers `UIView.animate { saveBar
   .setDirty(...) }`. UIKit opens an animation block.
5. The animate block's implicit "from" state captures every subview's
   current frame — all `.zero`, because the VC hasn't laid out yet.
6. The VC view is added to the hierarchy; bounds resolve to real values
   during the appearance window.
7. UIKit interpolates from the captured `.zero` to the resolved real
   bounds for **every subview**, not just the saveBar. The whole panel
   appears to "expand from origin".

### The fix

Reorder so initial state is loaded and synced **before** the binding
is registered:

```swift
override func viewDidLoad() {
  super.viewDidLoad()
  setupUI()
  viewModel.loadSettings()       // mutates VM, but no listener yet
  syncFieldsFromDraft()           // populates UI manually
  refreshDirtyState(animated: false)
  bindViewModel()                 // first onChange is now a real user mutation
}
```

First `onChange` fire is guaranteed to be a genuine user-driven
mutation, with view.frame already resolved — `animated: true` does
what the author intended.

### Why it's confusable with the iOS 26 layout regression

Both bugs share the same mechanism (UIKit captures `.zero` as "from"
and interpolates from origin). They differ in **who opens the animation
block**:

| Bug | Animation block opened by | Triggered by |
|---|---|---|
| iOS 26 `.zero`-frame settling | UIKit's appearance transition | `setViewController(_:for:)` / `setViewControllers(_:animated:)` on iOS 26.0–26.4 |
| Bind-before-load sync-fire | Your `UIView.animate { }` inside the bind callback | `viewModel.onChange` firing synchronously during viewDidLoad |

Both produce "expand from origin". One is platform-level, one is
sequencing-level. **An empty-body experiment distinguishes them
decisively** (see Diagnostic below).

### Diagnostic: empty-body test

If you suspect either bug, replace the detail VC's `viewDidLoad` body
with only a background color and the navigation chrome:

```swift
override func viewDidLoad() {
  super.viewDidLoad()
  navigationItem.largeTitleDisplayMode = .always
  view.backgroundColor = .systemRed
}
```

- **Red panel appears instantly, no animation** → the bug is in the
  data-sync / binding path. Look for `UIView.animate` reached during
  viewDidLoad via a synchronously-fired bind callback. Apply the
  bind-after-load reorder.
- **Red panel still expands from origin** → the bug is in the swap
  mechanism (iOS 26 layout regression). See `split-view-controller
.md` → "Detail Swap Settling Animation on iOS 26".

This test takes one build cycle and rules out half the universe of
candidate causes. Run it before reading further hypotheses.

### Differential check: find a sibling VC that doesn't animate

If two detail VCs share a swap pattern but only one animates, the swap
is innocent. Read both `viewDidLoad`s side-by-side and look for:

- A bind / observer registered before a synchronous load (the
  offender)
- vs. the cleaner VC binding only after sync setup, OR using only
  async loads (the safe pattern)

This was the path through the actual fix in this codebase: Customer
detail and Settings detail both used `secondaryNav.setViewControllers
([detail], animated: false)`. Customer mounted without animation;
Settings expanded from origin. The single difference was that Settings
detail VCs (LoyaltyDetailViewController, StoreInfoDetailViewController,
PaymentMethodsDetailViewController) bound onChange *before* sync
loadSettings, while Customer bound after. Once spotted, the fix was a
four-line reorder per VC.

## Sub-Layer Resolution Artifacts (iOS 26 regression)

On iOS 26.0–26.4 (at least), `UISplitViewController.setViewController
(_:for:)` and `UINavigationController.pushViewController(_:animated:)`
add the incoming VC's view with a `.zero` frame and `.zero`
safe-area insets *before* the appearance transition begins. Auto
Layout resolves the real values inside the transition window, and
every sub-element appears to animate from origin → final.

This produces an entire family of artifacts that **look** like
independent implicit animations:

- gradient banner "color crossfade"
- segmented control "pill slide"
- switch "thumb settle"
- labels "fade in"

They are not separate animations. They are the same `.zero → real`
Auto Layout resolve seen through different sub-layers.

**Diagnostic**: if you find yourself suppressing N+1 of these in one
session, the right fix is the layout cause, not another suppression
layer. See `split-view-controller.md` → "Detail Swap Settling
Animation on iOS 26".

Apple shipped a partial fix in iOS 26.2 for the `pushViewController`
path
(https://darjeelingsteve.com/articles/Fixing-UINavigationController-Push-Animation-Layout-Issues-on-iOS-26.html).
The `setViewController(_:for:)` path is still affected as of 26.4.

## Suppression Recipes

### Per Layer (preferred — narrow, durable)

```swift
// In the view's init:
layer.actions = [
  "bounds": NSNull(),
  "position": NSNull(),
]
```

Use this when the view's purpose is to display loaded content (status
banner, dashboard tile, settings row). It's a one-time declaration; no
per-call discipline needed.

### Per Call Site (when suppression must be conditional)

```swift
CATransaction.begin()
CATransaction.setDisableActions(true)
gradientLayer.colors = ...
CATransaction.commit()
```

Use when *most* of the time the animation is wanted but a specific
state change shouldn't animate (e.g. initial sync from a draft, then
animate user edits). Don't reach for this when the view is
fundamentally a content surface — set `layer.actions` instead.

### Per View (UIView animation block only)

```swift
UIView.performWithoutAnimation {
  // suppresses UIView.animate blocks that fire inside this scope,
  // does NOT reliably suppress CALayer implicit actions
}
```

This is necessary but rarely sufficient. Pair with `CATransaction
.setDisableActions(true)` when the goal is "no animations at all in
this scope".

### Per Layer Tree (defensive scrub — discouraged)

```swift
func scrub(_ view: UIView) {
  view.layer.removeAllAnimations()
  view.subviews.forEach(scrub)
}
scrub(viewController.view)
```

This works visually but is a *workaround* — it removes animations
*after* they've been scheduled. If you need this, audit upstream
first; the right fix usually exists.

## Anti-Pattern: Symptom Stacking

The hardest implicit-animation bugs are the ones where each suppression
layer fixes the *previous* symptom and reveals a new one. Pattern:

1. See a slide → wrap setViewController in `performWithoutAnimation`
2. Now the table content slides → wrap apply with
   `animatingDifferences: false`
3. Now a label fades → wrap `applyState()` in
   `CATransaction.disableActions`
4. Now the gradient still crossfades → wrap the configure call too
5. Now a switch thumb still moves → `setAnimationsEnabled(false)`
   globally

**Heuristic**: if you're adding suppression layer N+1, layer N was
probably already a workaround. Stop and find the real cause.

Steps when this triggers (run cheap-first):

1. **Empty-body test (one build cycle)** — replace the suspect VC's
   `viewDidLoad` body with `view.backgroundColor = .systemRed` and
   nothing else. If the symptom disappears, the bug is in the content
   path, not the swap / appearance mechanism. This eliminates entire
   hypothesis trees in minutes. See "Bind-Before-Load: The Sync-Fire
   Trap" → "Diagnostic".
2. **Differential check** — find a sibling VC mounted via the same
   path that doesn't show the bug. The difference between them is the
   cause, even if it looks unrelated to the suspected mechanism.
   Counterexamples beat correlations.
3. **Reproduce minimally** — strip the broken VC piece-by-piece. Bisect
   `viewDidLoad` calls until the trigger is one line. Read that line's
   transitive code path; the cause is rarely more than two hops away.
4. **Read vendor changelogs** — Apple Developer release notes / WWDC
   sessions for the relevant year. Search for the API in the issue.
5. **Web research** — same Stack Overflow / Twitter / blog post you'd
   write. Other developers have probably hit this exact case. **But**:
   a real bug + a real workaround on the internet can match your
   symptom and still be wrong for your codebase. Validate empirically
   (step 1) before adopting any community fix. Adopting an off-target
   fix burns more time than skipping research.
6. **Instruments → Core Animation profiler** — captures the actual
   animation keys + durations, telling you WHICH layer is animating
   WHICH property, not just "something is animating".
7. **Compare across iOS versions** if possible — same code, different
   sim runtime. If iOS 18 doesn't animate and iOS 26 does, it's a
   platform regression; if both animate, it's your code.

### Lessons from the bind-before-load investigation

- **Commit messages aren't ground truth.** A previous commit's stated
  reason for a refactor can be wrong about WHY it worked even when
  the refactor itself was correct. Always re-derive the why from the
  current code, especially when the refactor is one you're considering
  reverting.
- **A research-confirmed iOS bug can still be wrong for your symptom.**
  Darjeeling Steve + StackOverflow Q79844715 both describe real iOS 26
  swap regressions with real workarounds. Adopting their fix in a
  codebase that has the same *symptom* but a different *trigger*
  (synchronous bind-fire vs platform-level layout race) cost half a
  day. The empty-body test would have caught this in ten minutes.
- **Cap-vs-uncapped layouts both work or both break the same way.**
  Tested the hypothesis "max-width centered column is the trigger" by
  raising the cap from 720pt to 5000pt to disengage it. Animation
  persisted. One number, one build, hypothesis dead. Always run the
  decisive cheap experiment before writing the fix.

This whole reference exists because of one session where we stacked 4
suppression layers before stopping. The bind-before-load section
exists because of one session where we adopted a research-validated
iOS 26 fix for a bug that was actually a sequencing error. Don't be
either session.

## Mount-State Hygiene Checklist

For any detail VC, sync or async load:

- [ ] **Initial state is loaded + synced BEFORE binding onChange.**
      Order in viewDidLoad: `setupUI() → load() → sync() → bind()`.
      Never `bind() → load()` when load is synchronous — see
      "Bind-Before-Load: The Sync-Fire Trap" above.
- [ ] For async loads: `applyState()` called in `viewDidLoad` from the
      VM's *current* state, before the async `Task` fires — first paint
      reflects the best-known state, not empty
- [ ] VM is pre-warmed at composer construction time so by the time the
      user arrives the state is usually loaded
- [ ] Layer-level implicit animations on the view's gradient / status
      indicator are suppressed via `layer.actions = [... NSNull()]`
- [ ] `UISwitch` is sync'd with `setOn(_:animated: false)` on initial
      sync; subsequent user edits use the default animated setter
- [ ] First diffable apply is gated on `dataSource.snapshot()
      .numberOfItems > 0` (only animate diffs against existing on-screen
      content)
- [ ] No `CATransaction.setDisableActions` wrap on the VC's whole
      state-update method — that's a workaround; address the
      animations at the source layer instead

## iOS Version Notes

| Behavior | iOS 17 | iOS 18 | iOS 26.0–26.1 | iOS 26.2 | iOS 26.4 |
|----------|--------|--------|---------------|----------|----------|
| `CAGradientLayer.colors` implicit crossfade | yes | yes | yes | yes | yes |
| `UISegmentedControl` pill on delta change | yes | yes | yes | yes | yes |
| `UISwitch.isOn` animates by default | yes | yes | yes | yes | yes |
| Diffable `apply(_:animatingDifferences:true)` on first empty source animates each row in | yes | yes | yes | yes | yes |
| `UISplitViewController.setViewController(_:for:)` adds VC view with `.zero` frame (settling artifact) | no | no | **yes** | **yes** | **yes** |
| `UINavigationController.pushViewController` same `.zero` frame artifact | no | no | **yes** | fixed | fixed |
| `UISplitViewController` sidebar floats above content (Liquid Glass) | no | no | yes | yes | yes |
| `primaryBackgroundStyle = .none` removes sidebar background | yes | yes | **no** | no | no |
| `primaryBackgroundEffect = nil` removes sidebar background | n/a | n/a | yes | yes | yes |

The rows highlighted with **bold yes** / **no** are the deltas worth
remembering. The rest were stable across the range.

## Related References

- `split-view-controller.md` — the iOS 26 setViewController layout
  regression with the load-bearing fix
- `list-composition.md` → "First-Apply Animation Gate" — diffable apply
  pattern for sidebar-mounted detail panes
- `animation.md` — deliberate animation patterns (spring expand, fade
  defaults) when you actually want motion
