# Localized Formatting — Styled Arguments and Plurals

## When to Apply / Not for

Apply when a localized string interpolates values and part of it must be styled (a bold name, a colored count), or when its wording depends on a count.

Not for `.strings` escape syntax (→ [localizable-strings-escapes](localizable-strings-escapes.md)) nor for which bundle supplies the strings (→ [localization-bundle-discovery](localization-bundle-discovery.md)).

## Mark the Styled Span in the String, Never Search for the Value

Never locate an interpolated value with `range(of:)` to style it. The search hits the wrong occurrence when the value also appears in the template or in a translation ("Remove Ann from Ann's team"), and finds nothing when a formatter changed the value's spelling (number grouping, name formatting).

Put the markers in the localized string instead, so translators move them with the argument (catalog key `Delete **%@**?`), and style from the parsed runs.

## Markdown Parses the Arguments Too

`AttributedString(localized:)` parses Markdown after interpolation, so an argument's own characters are Markdown as well. Measured on the macOS 26 SDK: a display name `[click](https://evil.example)` becomes a live link, `*star` loses its asterisk, `` `x` `` turns into inline code. Interpolating an `AttributedString` instead of a `String` changes nothing.

For any argument the app does not control — names, titles, user text — interpolate a placeholder and substitute the real value after parsing:

```swift
extension AttributedString {
    /// Replaces `placeholder` with `value`, keeping the placeholder's attributes.
    mutating func fill(_ placeholder: String, with value: String) {
        guard let range = range(of: placeholder) else { return }
        let attributes = self[range].runs.first?.attributes ?? AttributeContainer()
        replaceSubrange(range, with: AttributedString(value, attributes: attributes))
    }
}

let placeholder = "\u{E000}"   // private-use character: cannot occur in a template or a translation
var text = AttributedString(localized: "Delete **\(placeholder)**?")
text.fill(placeholder, with: user.displayName)
```

Searching for the placeholder is safe exactly because it cannot appear anywhere else. Use a distinct private-use character per argument.

## UIKit Ignores Markdown Intents Until You Map Them

Markdown emphasis arrives as `inlinePresentationIntent`, which SwiftUI `Text` renders and UIKit text views do not — `label.attributedText = NSAttributedString(text)` shows plain text. Map the intent to UIKit attributes before converting:

```swift
for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
    text[run.range].uiKit.font = boldFont
}
label.attributedText = NSAttributedString(text)
```

## Plurals Come From the Catalog

Never branch on the count in code (`count == 1 ? "1 item" : "\(count) items"`). Languages use up to six plural categories (zero, one, two, few, many, other) and some use only one, so a two-way branch is wrong for most of them. Write `String(localized: "\(count) items")` and add the variations in the String Catalog with Vary by Plural; a string with two counts varies by each argument independently.
