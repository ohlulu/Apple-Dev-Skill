# Localizable.strings — Escape Sequences

The Apple `.strings` format is **not** generic Unicode-escape-friendly.
Get the case wrong and the parser silently drops the backslash and
leaves the escape characters as literal text in your UI.

## What works

| Escape       | Meaning                          |
|--------------|----------------------------------|
| `\n`         | newline                          |
| `\r`         | carriage return                  |
| `\t`         | tab                              |
| `\"`         | literal double quote             |
| `\\`         | literal backslash                |
| `\Uxxxx`     | Unicode codepoint, 4 hex digits — **capital U** |
| `\U0001F600` | Unicode codepoint, 8 hex digits  |

## What does NOT work

| Looks like  | Actually parses as | Why                                 |
|-------------|--------------------|--------------------------------------|
| `\u2014`    | `u2014`            | lowercase `\u` is not recognized; parser strips the backslash and keeps the rest |
| `\x14`      | `x14`              | hex-byte escape is not a thing in `.strings` |
| `\0`        | `0`                | null-escape is not recognized |

The failure mode is silent — Xcode does not warn, the strings file
compiles, and the literal characters show up at runtime in the UI.

## Preferred approach

**Just put the actual UTF-8 character in the file.** `.strings` files
are UTF-8 (or UTF-16) by convention; em dash, ellipsis, smart quotes
all render directly:

```
// ✅ Direct UTF-8 — readable in source, correct at runtime
"some.key" = "Draft — hidden from the engine.";
"other.key" = "Loading…";
"quoted.key" = "He said "hi".";

// ❌ Lowercase \u — runtime shows literal "u2014"
"some.key" = "Draft \u2014 hidden from the engine.";

// ⚠️ Uppercase \U works but harms readability
"some.key" = "Draft \U2014 hidden from the engine.";
```

The only reason to reach for `\U` is when the surrounding tooling
mangles non-ASCII characters (rare with modern editors / git
configurations).

## Audit one-liner

Catch lowercase `\uXXXX` escapes across all `.strings` files:

```bash
grep -rn '\\u[0-9a-fA-F]\{4\}' **/*.strings
```

If anything turns up, replace with the literal UTF-8 character.

## Checklist

- [ ] Use literal UTF-8 characters for `—`, `…`, `"`, `"`, etc.
- [ ] Reserve `\Uxxxx` (capital U) for the rare cases where source-level
      literal characters can't survive the toolchain
- [ ] CI / pre-commit: grep for `\u[0-9a-fA-F]{4}` in `.strings` to
      catch the lowercase trap before it ships
