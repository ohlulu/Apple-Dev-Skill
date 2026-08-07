# Apple Dev Skill
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/ohlulu/Apple-Dev-Skill/blob/main/LICENSE)

Expert Apple platform development guidance for any AI coding tool that supports the [Agent Skills open format](https://agentskills.io/home) — UIKit patterns, Xcode/Tuist project setup, and Swift coding conventions for app development.

## Who this is for
- Teams building or maintaining UIKit-based iOS/iPadOS apps
- Developers setting up Xcode projects with Tuist, XcodeGen, or pure Xcode
- Anyone reviewing Swift code in an Apple app context

## How to Use This Skill

### Option A: Using skills.sh
```bash
npx skills add https://github.com/ohlulu/Apple-Dev-Skill --skill apple-dev-skill
```

### Option B: Using pi package manager
```bash
pi install https://github.com/ohlulu/Apple-Dev-Skill
```

### Option C: Manual install
1. Clone this repository
2. Install or symlink `apple-dev-skill/` following your tool's skills installation docs

## What's Inside

Three domains unified under a single Topic Router. Reference files load on demand, so your agent gets deep guidance only for the topic at hand.

### UIKit / UI Patterns

| Reference | Coverage |
|-----------|----------|
| file-structure | Property ordering, extensions, layout placement for VC / View / Cell |
| animation | Duration, curve, fade defaults, stagger reveal |
| list-composition | Row/item controllers, section controllers, load-more, pagination, diffable, compositional layout |
| composer | Programmatic controller instantiation, dependency wiring, navigation closures |
| testing-principles | Test levels, async spies, assertion strategy, memory leak tracking |
| testing | UIKit lifecycle simulation, semantic list helpers, pagination integration tests |
| uiview-representable | SwiftUI bridging — diff-based updates, coordinator callbacks, pre-rendered bitmaps |
| *(43 reference files total, including iOS 26 behavior changes, split view, implicit animations, diffable, iCloud/cloud backup)* | |

### Xcode / Project Setup

| Reference | Coverage |
|-----------|----------|
| xcode-project-setup | Workspace layout, synced folders, SPM deps, app identity, shared schemes, gotchas |
| xcconfig | Hierarchy, naming, inline vs file, Xcode upgrade SOP |
| build-phases | SwiftFormat hook, SwiftLint, Firebase Crashlytics, sandboxing |
| makefile | Recipe-vs-script split, simulator vs device targeting, DerivedData strategy, result verification |
| tuist-spm-integration | Native vs XcodeProj-based, migration steps |
| xcodebuild-error-detection | Three-way result verification, test crash detection |

### Swift Coding Style

| Reference | Coverage |
|-----------|----------|
| swift-style | Type design, protocols, error handling, API design, file organization |

Non-opinionated: focuses on correctness and practical patterns, not architecture or code style enforcement.

## Skill Structure
<!-- BEGIN REFERENCE STRUCTURE -->
```text
apple-dev-skill/
  SKILL.md
  references/
    alignment.md
    animation.md
    associated-objects.md
    autolayout-spacing.md
    build-phases.md
    cell-registration.md
    cli-distribution-signing.md
    cloud-backup-providers.md
    composer.md
    compound-cell-row-animation.md
    diffable-data-source.md
    file-structure.md
    icloud-ubiquity.md
    image-resizing.md
    implicit-animations.md
    ios-26-behavior-changes.md
    keyboard-avoidance.md
    label-wrapping.md
    list-composition.md
    localizable-strings-escapes.md
    localization-bundle-discovery.md
    makefile.md
    Makefile.template
    menu-vs-popover.md
    navigation-bar-appearance.md
    overflow-detection.md
    photo-picker.md
    popover-tooltip.md
    self-sizing.md
    shadow-and-clipping.md
    split-view-controller.md
    step-transition-sizing.md
    swift-style.md
    testing-principles.md
    testing.md
    tuist-spm-integration.md
    uibutton-configuration.md
    uibutton-icon-badge.md
    uiview-representable.md
    view-wrapping.md
    xcconfig.md
    xcode-close.applescript
    xcode-project-setup.md
    xcodebuild-error-detection.md
    zoomable-image-preview.md
```
<!-- END REFERENCE STRUCTURE -->

## Migration from UIKit Expert Skill

This skill was previously named `uikit-expert-skill`. It now also includes content from `xcode-skill` and `swift-coding-style`. If you had the old skill installed, uninstall it and install this one.

## Contributing

Contributions welcome — fix incorrect guidance, add modern APIs, expand reference coverage. Keep content focused on Apple app development.

## License

MIT License. See [LICENSE](LICENSE) for details.
