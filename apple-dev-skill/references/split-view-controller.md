# UISplitViewController on iOS 26

## iOS 26 Behavior Change — Primary Column Is an Overlay

On iOS 26, `UISplitViewController(style: .doubleColumn)` renders the primary column as a **floating glass card overlaid above the secondary column**, not beside it. The secondary column's view bounds span the **entire screen width**, with the master visually layered on top.

This is the Liquid Glass sidebar treatment. It is the default — there is no opt-out via `preferredSplitBehavior = .tile` (the setting is accepted but does not flatten the overlay).

### Symptom

- Detail content draws under the floating master and gets clipped on the leading edge
- Card titles, form fields, and section headers appear to start *inside* the master card
- Only obvious when the detail has wide content; an empty placeholder secondary looks fine (which masks the bug during initial development)

### Root Cause

Detail view controllers anchored to `view.leadingAnchor` / `view.trailingAnchor` extend from x=0 to the full screen width. iOS does not clip the secondary VC's view to the space beside the master — it expects the VC to use the safe-area guide, into which iOS folds the floating master's frame.

### Fix

Anchor scrollable detail content to `view.safeAreaLayoutGuide.leadingAnchor` / `trailingAnchor`:

```swift
NSLayoutConstraint.activate([
  scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
  scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
  scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
  scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
])
```

iOS automatically inset `safeAreaLayoutGuide` past the master overlay. No manual offset, no observation of split-view state, no size-class branching needed.

## Composer Configuration Checklist

| Step | Required? | Why |
|------|-----------|-----|
| Wrap primary in `UINavigationController` with `prefersLargeTitles = true` | Yes | A bare VC as primary triggers an even more aggressive sidebar pill style. The nav controller anchors the column visually. |
| Call `split.setViewController(_, for: .primary)` before `.secondary` | Yes | Standard ordering. |
| Set an initial secondary VC (real or placeholder) **before returning the split** | Yes | If secondary is `nil` when the split first appears, iOS commits to a single-column sidebar layout for that lifetime. Setting secondary lazily from `viewDidLoad` is too late. |
| `preferredSplitBehavior = .tile` | Optional | Honored on iOS 18 and earlier; ignored on iOS 26. Set it anyway as documentation of intent. |
| `applyColumnAffordancePolicy()` (project helper) | Yes (regular size class) | Suppresses the auto-inserted column toggle button + edge swipe on iPad full-screen; restores them on compact for accessibility. |

## Anti-Patterns

| Attempt | Why it fails |
|---------|--------------|
| Replace `UISplitViewController` with a custom `HStackView` (master + detail) | Loses system traits: column affordance, compact-size collapse, sheet presentation anchoring. Works for static layouts but breaks Stage Manager / Slide Over. |
| Drop the `UINavigationController` wrapper on primary | iOS 26 promotes the bare VC to an even more pronounced sidebar pill. The wrapper is **load-bearing**, not just cosmetic chrome. |
| Set `split.preferredSplitBehavior = .tile` and expect a flush column pair | Setting is accepted but iOS 26 still applies the overlay treatment. |
| Make the master view opaque to hide bleed-through | Doesn't address the layout issue — content still clips at the safe-area edge once the user resizes the window. |
| Bootstrap secondary from the master's `viewDidLoad` via a callback | Fires after the split commits its initial layout decision. Mount the secondary in the composer instead. |

## Diagnostic

When you suspect overlay clipping, dump the accessibility frame of detail content and look for **width values that span the whole screen**:

```bash
axe describe-ui --udid <UDID>
```

If a card or scroll view inside the detail reports `width: 949` (or whatever ≈ full screen width) instead of `≈ secondary column width`, the detail is anchored to `view.leadingAnchor` instead of the safe-area guide. Frame data is more diagnostic than screenshots here — the screenshot only shows the visible portion, the frame dump reveals the actual extent.

## Reference Implementations

In this codebase, `CustomerDetailViewController` and `TransactionDetailViewController` are the canonical examples. Copy their scroll-view anchoring pattern (`safeAreaLayoutGuide` for leading/trailing) when building any new detail VC that sits in a `UISplitViewController` secondary column.
