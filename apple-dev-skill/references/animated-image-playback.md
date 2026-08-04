# Custom Animated-Image Playback in UIImageView Subclasses

Traps for building (or reviewing) a UIImageView subclass that plays animated
images by delivering decoded frames through `image` updates — the architecture
used when wrapping SDWebImage's `SDAnimatedImagePlayer`, or any custom
frame-engine.

## When to Apply / Not for

Apply when a UIImageView subclass drives per-frame rendering itself (custom
engine, `SDAnimatedImagePlayer`, CADisplayLink + frame buffer). Not for plain
`UIImageView.animationImages` usage, and not for SwiftUI.

## Trap 1: Never override `isAnimating` on an image-setting renderer

UIKit's image-display path consults `isAnimating` before writing a new image
into the layer: when it returns `true`, UIKit assumes a native
`animationImages` animation owns the layer contents and **skips the write**
(`UIImageView._updateState` early-returns before `_setImageViewContents:`;
confirmed against iOS 17.4 UIKitCore disassembly). A subclass that overrides
`isAnimating` to report its own engine state therefore freezes its own
rendering: every `super.image = frame` updates the model value only.

Symptom signature — looks impossible until you know the mechanism:

- frames arrive on schedule, each with distinct pixel content;
- `super.image = frame` executes on the main thread every tick;
- layer *property* changes (e.g. `borderWidth`) still render;
- the screen shows the first frame forever. The first frame displays because
  it was set before the engine attached (while `isAnimating` was still false).

Rule: expose engine state through a separate property (`isPlaying`), never
through the `isAnimating` override.

Why SDAnimatedImageView gets away with it: upstream overrides `isAnimating`
**and** renders through `displayLayer:` + a stored `currentFrame`, bypassing
the `image` setter entirely. The override and the rendering path are a
load-bearing pair — copying the API surface without the rendering half ships
the freeze.

## Trap 2: Visibility-driven pause needs a self-owned resume path

Pausing playback when the view stops being visible (ancestor hidden, alpha 0,
off-window) is the right call for CPU/memory — but UIKit gives descendants
**no hook** when an *ancestor* becomes visible again. Two facts combine into a
permanent freeze:

- UICollectionView (iOS 15+) pools offscreen cells by setting `hidden = YES`
  **in place** — the cell never leaves the window, so `didMoveToWindow` never
  fires on its subviews;
- when the cell scrolls back for the same index path it is un-hidden without
  reconfiguration — no `prepareForReuse`, no cell-for-item, no new session.

So "pause on invisible" + "resume on UIKit hook" covers every case except the
most common one: scroll out, scroll back.

Fix pattern: a low-frequency watchdog that exists only during the gap —
scheduled when (wants-playing && engine attached && not visible), rechecks
visibility on each tick, resumes and self-cancels. Add the timer to
`RunLoop.main` in `.common` modes: re-display happens mid-scroll, when the
main run loop is in tracking mode and default-mode timers do not fire.
Invalidate in `deinit` (block-based timers with `[weak self]` do not retain
the view, but the run loop retains the timer).

YY-era note: `YYAnimatedImageView` never had this bug because it never pauses
on ancestor visibility — at the cost of burning CPU for every pooled-hidden
cell. If a migration away from YY adds visibility gating, it must add the
resume path in the same change.

## Probe ladder: "frames delivered but screen frozen"

When playback state, frame delivery, and visibility all check out yet the
screen is static, walk up this ladder instead of re-reading state logs:

1. **State log** — wants/visible/engine at play time; wire/session lifecycle
   (rules out intent loss and session churn).
2. **Content fingerprint** — hash a prefix of `cgImage.dataProvider` bytes per
   delivered frame (rules out "distinct objects, identical pixels").
3. **Visual layer probe** — toggle a layer property per frame
   (`layer.borderWidth = index % 2 == 0 ? 4 : 0`): flashing proves the view
   is on screen and its layer renders, isolating the failure to the
   image-display path specifically.
4. If 1–3 all pass and the image still doesn't change, the write into layer
   contents is being skipped — suspect Trap 1's mechanism (or any state that
   makes UIKit think it owns the contents, e.g. `isHighlighted` with
   highlighted imagery).

Step 3 is the discriminator that turns "impossible" into "one specific UIKit
code path"; run it before reaching for Instruments or disassembly.
