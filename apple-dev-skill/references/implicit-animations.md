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

Steps when this triggers:

1. **Reproduce minimally** — strip the problem to the smallest VC + view
   hierarchy that exhibits it. Often makes the cause obvious.
2. **Read vendor changelogs** — Apple Developer release notes / WWDC
   sessions for the relevant year. Search for the API in the issue.
3. **Web research** — same Stack Overflow / Twitter / blog post you'd
   write. Other developers have probably hit this exact case.
4. **Instruments → Core Animation profiler** — captures the actual
   animation keys + durations, telling you WHICH layer is animating
   WHICH property, not just "something is animating".
5. **Compare across iOS versions** if possible — same code, different
   sim runtime. If iOS 18 doesn't animate and iOS 26 does, it's a
   platform regression; if both animate, it's your code.

This whole reference exists because of one session where we stacked 4
suppression layers before stopping. Don't be that session.

## Mount-State Hygiene Checklist

For any detail VC that loads state asynchronously:

- [ ] `applyState()` called in `viewDidLoad` from the VM's *current*
      state, before the async `Task` fires — first paint reflects the
      best-known state, not empty
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
