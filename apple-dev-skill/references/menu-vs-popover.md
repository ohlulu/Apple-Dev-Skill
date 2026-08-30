# UIMenu vs UIPopover — Selection Pattern Decision

## Decision Rule

Ask these questions in order. Stop at the first match.

| Question | UIMenu | UIPopover |
|----------|--------|-----------|
| Options are plain text or text + icon? | ✅ | — |
| Need checkmark on current selection? | ✅ built-in `.on` state | Manual drawing |
| Select and dismiss immediately? | ✅ | — |
| Need custom views inside (slider, toggle, color swatch, multi-step)? | ❌ cannot | ✅ |
| User stays and interacts before dismissing? | ❌ | ✅ |
| Care about sizing bugs on iPhone? | ✅ zero risk | ⚠️ manual `preferredContentSize` |

**One-liner**: if the content is a flat list of text options with select-and-dismiss behavior, use UIMenu. Use UIPopover only when the content requires custom UI or multi-step interaction.

## UIMenu

### Strengths

- **Zero sizing issues** — system renders and positions automatically
- **Native checkmark** — `UIAction(state: .on)` / `.off`
- **Sub-menus** — nested `UIMenu(children:)` for hierarchical options
- **Haptic + blur backdrop** — free
- **Minimal code** — attach to any `UIButton` or `UIBarButtonItem`
- **≤ ~15 items** — system scrolls automatically beyond that

### Implementation pattern

```swift
let actions = options.map { option in
    UIAction(
        title: option.displayName,
        state: option == current ? .on : .off
    ) { [weak self] _ in
        self?.handleSelection(option)
    }
}
button.menu = UIMenu(children: actions)
button.showsMenuAsPrimaryAction = true
```

To rebuild the menu when selection changes, reassign `button.menu` with updated states.

### Limitations

- Cannot embed custom views (pickers, sliders, toggles, swatches)
- Row height, font, spacing controlled by system — no customization
- No progressive disclosure or multi-step interaction within the menu
- Destructive style (`.destructive`) available but limited to red text

## UIPopover

### Strengths

- **Full custom UI** — any `UIViewController` as content, including brand-specific visual treatment
- **Stays open** — user can interact without auto-dismiss
- **Dynamic sizing** — update `preferredContentSize` to animate height changes

### Costs

- **Manual sizing** — must calculate `preferredContentSize`; errors cause clipping or excessive whitespace
- **iPhone fallback** — defaults to full-screen sheet; requires `UIPopoverPresentationControllerDelegate` returning `.none` to force popover
- **Arrow alignment** — must set `sourceView`, `sourceRect`, `permittedArrowDirections`
- **Custom chrome** — separators, checkmarks, highlights, scroll handling all manual
- **More code** — dedicated VC, delegate conformance, layout constraints

### Common sizing pitfalls

```swift
// ❌ Forgets separators, padding, safe areas
let height = CGFloat(itemCount) * rowHeight
preferredContentSize = CGSize(width: 220, height: height)

// ✅ Account for all content
let separators = CGFloat(itemCount - 1) * separatorHeight
let padding: CGFloat = 16 // top + bottom
preferredContentSize = CGSize(width: 220, height: CGFloat(itemCount) * rowHeight + separators + padding)
```

Even with correct math, the popover arrow and system insets can still clip content on small screens.

## Examples by use case

| Use case | Recommendation | Why |
|----------|---------------|-----|
| Sort order (newest, oldest, A-Z) | UIMenu | Flat text list, select-and-dismiss |
| Date format (yyyy/MM/dd, etc.) | UIMenu | Flat text list, checkmark on current |
| Theme picker with color swatches | UIPopover or push | Custom UI (color previews) |
| Font picker with live preview | UIPopover | Custom UI + stays open to compare |
| Filter panel (toggles + range sliders) | UIPopover or sheet | Multi-step, custom controls |
| Language/region selector (3-5 items) | UIMenu | Small flat list |
| Emoji picker | Sheet or popover | Grid layout, scrollable, custom |
| "More" actions (edit, delete, share) | UIMenu | Standard action list |

## Migration: Popover → Menu

When replacing an existing popover with UIMenu:

1. Delete the popover VC file
2. Remove `UIPopoverPresentationControllerDelegate` conformance
3. Remove `sourceView` / `sourceRect` / `permittedArrowDirections` setup
4. Build `UIMenu(children:)` with `UIAction` per option
5. Assign to button's `.menu` property + `.showsMenuAsPrimaryAction = true`
6. Regenerate project if using file-based build systems (Tuist, etc.)
