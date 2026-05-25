# CLI Distribution Signing (xcodebuild exportArchive)

## Problem

`xcodebuild -exportArchive -exportOptionsPlist ...` with `method=app-store-connect` and `signingStyle=automatic` does **not** sign against a local Apple Distribution certificate. Instead it asks Apple to mint a one-shot **cloud-signed** cert + profile at export time.

Cloud signing in **CLI mode** authenticates using the Apple ID OAuth session cached by Xcode (`Xcode → Settings → Accounts`). An App Store Connect **API key is not a substitute** — the API key cannot create distribution certs/profiles on the fly, even with full role permissions.

If no Apple ID account is signed in to Xcode on the machine, every CLI export fails. The error message depends on which auth flags you pass and is misleading either way.

## Symptoms

| Flags passed to `xcodebuild -exportArchive` | Error |
|---|---|
| None (default) | `Failed to find an account with App Store Connect access for team <TEAM_ID>` |
| `-authenticationKeyPath / -authenticationKeyID / -authenticationKeyIssuerID` | `Cloud signing permission error` + `No signing certificate "iOS Distribution" found` |

Both errors mean the **same thing**: cloud signing has no interactive session to fall back on. The second error is especially deceptive — it sounds like a missing local cert problem, but a local Apple Distribution cert is not what `automatic` signing actually wants.

## Fix (one-time per machine)

1. Open Xcode → **Settings → Accounts**
2. Add the Apple ID that belongs to the team (account-holder or admin role on App Store Connect)
3. Let Xcode finish "Loading…" the team membership

That is the whole fix. No script changes, no export plist edits, no certs to install, no provisioning profile downloads.

After this, `xcodebuild -exportArchive` from any shell — including from a Makefile, CI script, or release pipeline — will reuse the cached OAuth session for cloud signing and succeed.

## Anti-Patterns (do NOT do these)

| Wrong reflex | Why it fails |
|---|---|
| `asc certificates create --certificate-type DISTRIBUTION` to mint a local Apple Distribution cert | Wastes a cert slot; `signingStyle=automatic` still tries cloud signing first and ignores it. Also irreversible without revoking. |
| Adding `-authenticationKeyPath` etc. to fix the first error | Silences the *account* error but exposes the *cloud signing permission* error — same root cause, different message. |
| Switching to `signingStyle=manual` and shipping a `.p12` + `.mobileprovision` to every dev/CI machine | Works but adds a secret-management burden and yearly cert renewal pain. Use only if cloud signing is genuinely unavailable (e.g. headless CI with no GUI Xcode login). |
| Falling back to Xcode Organizer GUI for every release | Hides the missing-account state and breaks any release automation. Fix the account once, keep CLI flow. |

## Quick Diagnosis

```bash
# Is cloud signing wired up?
defaults read MobileMeAccounts 2>/dev/null | grep -c AccountID   # >= 1 = yes
ls ~/Library/Developer/Xcode/UserData/IDEAccounts/ 2>/dev/null   # exists = yes

# Are there any local distribution identities? (usually NO, and that's fine)
security find-identity -v -p codesigning | grep -E "Apple Distribution|iPhone Distribution"
```

If the first check returns 0 / no directory, the fix is the three-step Xcode account add above. The second check returning empty is **not** a problem — cloud signing does not need a local distribution identity.

## Headless CI Exception

The Xcode-account approach assumes a developer machine where someone can log in interactively once. For fully headless CI runners (e.g. GitHub Actions macOS images), you genuinely need `signingStyle=manual` with a stored `.p12` + provisioning profile, or a tool like fastlane match. That is a separate workflow — do not mix it into a developer-machine release script.
