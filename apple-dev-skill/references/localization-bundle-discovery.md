# Localization — Bundle Discovery & the Settings Language Picker

iOS decides whether to show the per-app **Preferred Language** row in
Settings → Apps → [App] by inspecting the **main app bundle's**
localization information. Frameworks that ship `.lproj` resources are
ignored for this discovery, even when they hold every translated string
the app actually displays.

If your app builds successfully, runs in two languages, and yet
Settings shows no language picker, this is almost always the cause.

## Where iOS looks

In order, iOS uses the main bundle's:

1. `CFBundleLocalizations` array in `Info.plist` (explicit declaration), or
2. `*.lproj` folders directly under the `.app/` root (implicit discovery)

If neither yields more than one entry, the app is treated as
single-language and the Preferred Language row is hidden. Framework
bundles under `Frameworks/*.framework/` are **not** consulted for this
decision.

## The framework-only trap

Many modular projects keep all `.strings` in a dedicated resources
framework so feature modules can share keys. The runtime cost is zero
— `Bundle.module` resolves correctly inside the framework — but the
main bundle ends up with no `.lproj` folders at all.

```
DingPOS.app/
├── Info.plist                        ← only CFBundleDevelopmentRegion = "en"
├── DingPOS                            (executable)
└── Frameworks/
    └── Resources.framework/
        ├── en.lproj/Localizable.strings
        └── zh-Hant.lproj/Localizable.strings
```

iOS sees one language at the app level and hides the picker.

## Fix: declare `CFBundleLocalizations` explicitly

Add two keys to the **app** target's `Info.plist`:

```
<key>CFBundleLocalizations</key>
<array>
    <string>en</string>
    <string>zh-Hant</string>
</array>
<key>CFBundleAllowMixedLocalizations</key>
<true/>
```

- `CFBundleLocalizations` — the contract with the system. List every
  language the app supports, matching the `*.lproj` folder names that
  exist in your resource framework.
- `CFBundleAllowMixedLocalizations` — allows the system to load
  localized resources from a different bundle than the app's primary
  language. Required when the actual strings live in a sub-framework.

Tuist `Project.swift` example:

```swift
infoPlist: .extendingDefault(with: [
    // All .strings live in Resources.framework, so the main bundle
    // has no .lproj folders. Without these keys iOS treats the app
    // as English-only and hides the Settings language picker.
    "CFBundleLocalizations": ["en", "zh-Hant"],
    "CFBundleAllowMixedLocalizations": true,
])
```

Keep the array in sync with the actual `.lproj` folders. A grep audit:

```bash
find . -name "*.lproj" -type d | grep -v DerivedData | sort -u
```

## Verification

After building, inspect the produced `Info.plist`:

```bash
plutil -p path/to/YourApp.app/Info.plist | grep -A3 "CFBundleLocalizations\|CFBundleAllowMixed"
```

Expected output:

```
"CFBundleAllowMixedLocalizations" => true
"CFBundleLocalizations" => [
  0 => "en"
  1 => "zh-Hant"
]
```

Then, **delete and reinstall the app** on the simulator or device. The
Settings language picker is populated from a cached snapshot taken at
install time; updating an already-installed app may not refresh it.

## Relationship to `CFBundleDevelopmentRegion`

`CFBundleDevelopmentRegion` is **not** the supported-languages list.
It only declares the fallback language used when no localized resource
matches the user's preferred languages. Leaving it alone (`en` is the
common default) is correct — adding `CFBundleLocalizations` does not
require changing it.

## Why not just put an empty `.lproj` in the app?

You can technically put an empty `en.lproj/` and `zh-Hant.lproj/` in
the app target to satisfy implicit discovery, but this is fragile:

- The folders must contain at least one resource or some build systems
  prune them.
- The relationship between two empty folders and "this app is
  localized" is invisible to the next developer.
- The explicit `CFBundleLocalizations` declaration documents intent at
  the point any reviewer would look first.

Prefer the explicit declaration.

## Common follow-on symptoms

| Symptom                                              | Likely cause |
|------------------------------------------------------|--------------|
| Settings picker present, but selecting a language has no effect | App reads strings via `NSLocalizedString` from `Bundle.main` instead of the framework's bundle. Switch to `Bundle.module` or a typed `L10n.tr(...)` helper bound to the resource bundle. |
| Picker shows the wrong language name (e.g. "中文" instead of "繁體中文") | `CFBundleLocalizations` entry uses `zh` instead of `zh-Hant`; iOS displays whatever you declare. Match the actual `.lproj` folder. |
| Picker present on first install, disappears after an update | The update changed `CFBundleLocalizations` or removed an `.lproj`. The Settings cache holds the old snapshot until reinstall. |

## Checklist

- [ ] All `.lproj` folders enumerated (`find . -name "*.lproj" -type d`)
- [ ] `CFBundleLocalizations` declared in the **app** target's `Info.plist`
- [ ] `CFBundleAllowMixedLocalizations = true` when strings live in a sub-framework
- [ ] Array entries match actual `.lproj` folder names exactly
- [ ] Verified via `plutil -p YourApp.app/Info.plist`
- [ ] App **uninstalled and reinstalled** to refresh the Settings cache
