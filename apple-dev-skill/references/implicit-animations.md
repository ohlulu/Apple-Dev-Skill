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

The fix is a reorder inside `viewDidLoad`, never a change to the swap
mechanism.

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

Steps when this triggers, cheap-first. Each step either kills a
hypothesis or promotes it, so never skip ahead to writing the fix:

1. **Empty-body test** — one build cycle, described under
   "Bind-Before-Load: The Sync-Fire Trap" → "Diagnostic". If the
   symptom survives an empty `viewDidLoad`, the content path is
   innocent and entire hypothesis trees die at once.
2. **Differential check** — find a sibling VC mounted via the same
   path that doesn't show the bug. The difference between them is the
   cause, even when it looks unrelated to the suspected mechanism.
   Counterexamples beat correlations.
3. **Bisect `viewDidLoad`** until the trigger is one line, then read
   that line's transitive path; the cause is rarely more than two hops
   away.
4. **Vendor changelogs and web research** — Apple release notes, WWDC
   sessions, and the exact API name. A real platform bug with a real
   community workaround can match your symptom while your trigger is
   different (a sequencing error vs a platform layout race), so
   re-validate any adopted fix with step 1. An off-target fix costs
   more than the ten-minute experiment.
5. **Geometry logging** — log each suspect view's `frame` / `bounds` /
   `transform` on every layout pass. The numbers tell you WHICH layer
   is resolving WHICH property; visual inspection can't. (Instruments'
   Core Animation profiler answers the same question with animation
   keys + durations — suggest it to the user as a manual step; do not
   attempt to drive it yourself.)
6. **Compare across iOS versions** — same code, different sim runtime.
   If iOS 18 doesn't animate and iOS 26 does, it's a platform
   regression; if both animate, it's your code.

One rule that does not fit the ladder: **re-derive the "why" from
current code, not commit messages.** A commit's stated reason can be
wrong about why the change worked even when the change itself was
correct, so extending a refactor on the strength of its message
cargo-cults a misdiagnosis.

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
- [ ] First diffable apply is gated on `dataSource.snapshot()
      .numberOfItems > 0` (only animate diffs against existing on-screen
      content)
- [ ] No `CATransaction.setDisableActions` wrap on the VC's whole
      state-update method — that's a workaround; address the
      animations at the source layer instead

## Related References

- `ios-26-behavior-changes.md` — the authoritative per-version delta
  table. Everything catalogued above is a long-standing UIKit default
  except the `.zero`-frame settling artifacts, which are iOS 26
  regressions.
- `split-view-controller.md` — the iOS 26 setViewController layout
  regression with the load-bearing fix
- `list-composition.md` → "First-Apply Animation Gate" — diffable apply
  pattern for sidebar-mounted detail panes
- `animation.md` — deliberate animation patterns (spring expand, fade
  defaults) when you actually want motion
