# CLI Distribution Signing (xcodebuild exportArchive)

## Problem

`xcodebuild -exportArchive -exportOptionsPlist ...` with `method=app-store-connect` and `signingStyle=automatic` does **not** sign against a local Apple Distribution certificate. It asks Apple to mint (or reuse) a **cloud-managed** Apple Distribution cert + profile at export time. The private key never leaves Apple; the machine holds no `.p12` and no `.mobileprovision`.

Cloud signing needs *something* to authenticate the request. There are two sources, and which one `xcodebuild` uses decides whether your release script survives a machine change:

| Auth source | How xcodebuild picks it | Failure mode |
|---|---|---|
| Xcode GUI account session (Xcode → Settings → Apple Accounts) | Default when no `-authenticationKey*` flags are passed | Session expiry or an upload rejection silently empties `DVTDeveloperAccountManagerAppleIDLists`; every CLI export dies until someone re-logs in with password + 2FA. GUI can still *show* the account while xcodebuild sees none. Not portable to another Mac or CI. |
| App Store Connect **team API key** with the **Admin** role | `-allowProvisioningUpdates -authenticationKeyPath <.p8> -authenticationKeyID <id> -authenticationKeyIssuerID <issuer>` on both `archive` and `-exportArchive` | Only fails if the `.p8` is missing or the key role is too low. Ignores the GUI account state entirely. Portable: copy one `.p8`. |

**Use the API key.** The GUI-session path is what Xcode falls back to, not a design.

## Symptoms and what they actually mean

| Error | Real cause | Fix |
|---|---|---|
| `Failed to Use Accounts` / `Failed to find an account with App Store Connect access for team <TEAM>` | No `-authenticationKey*` flags, and the Xcode account session is gone | Add the three flags; do not re-login in the GUI as the fix |
| `Cloud signing permission error` + `No signing certificate "iOS Distribution" found` | The API key's role is **App Manager or Developer**. Cloud-managed distribution certs require Admin (Apple: "Required role: Account Holder or Admin"). The second line is a red herring — cloud signing never wanted a local distribution identity | Generate a new team key with the Admin role (Account Holder / Admin only, Users and Access → Integrations → Team Keys). A key's role cannot be edited after creation |
| `Your account already has an Apple Development signing certificate for this machine, but its private key is not installed` | Ephemeral CI: the **archive** step still signs with a local Apple Development identity, and every fresh runner re-mints one until the per-account cap | Store a dev `.p12` and import it on the runner, or switch that pipeline to manual signing. A persistent second Mac does not hit this — it mints once and reuses |

## Verified (2026-09-09, Xcode 26, team TSTQSY2TJN)

Export with an Admin key while both Xcode GUI accounts failed to load (`Invalid credentials in keychain … missing Xcode-Username` in the log): `** EXPORT SUCCEEDED **`, `DistributionSummary.plist` → `type = Cloud Managed Apple Distribution`, IPA `codesign -dvv` → `Authority=Apple Distribution: … (TSTQSY2TJN)`. The same team's App Manager key is documented by several independent CI logs to fail at the `Cloud signing permission error` line.

## Recipe

```bash
ASC_KEY_ID="${ASC_KEY_ID:-<ADMIN_KEY_ID>}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-<ISSUER_UUID>}"
ASC_PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

xcodebuild -workspace App.xcworkspace -scheme App \
  -destination 'generic/platform=iOS' -archivePath /tmp/App.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  clean archive

xcodebuild -exportArchive -archivePath /tmp/App.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/AppExport \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

- `ExportOptions.plist` stays `signingStyle=automatic`, `destination=upload`; the upload uses the same key.
- `~/private_keys/` is the directory Apple's own `altool` / `notarytool` search, so a new machine needs exactly one file copied there. Key ID and Issuer ID are not secrets; the `.p8` is, and Apple keeps no copy.
- Keep the Admin key separate from the key day-to-day tooling (`asc`) uses. The release script is the only consumer that needs Admin.
- Env var names match the `asc` CLI's (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_PATH`), so a CI that sets them once drives both the signer and the ASC tooling. If those env vars point at a non-Admin key on a packaging machine, the export fails with the permission error above — unset them.

## Anti-patterns

| Wrong reflex | Why it fails |
|---|---|
| Re-logging into Xcode → Settings → Accounts whenever export dies | Works for one release, then the session drops again. It also hides the dependency, so the next machine or CI is a surprise |
| `asc certificates create --certificate-type DISTRIBUTION` to mint a local Apple Distribution cert | `signingStyle=automatic` ignores it and still cloud-signs; the cert wastes a slot and its private key is now a thing you have to keep |
| Reading `No signing certificate "iOS Distribution" found` as "install a cert" | It is the key-role error's second line. Fix the role |
| `signingStyle=manual` + `.p12` + `.mobileprovision` on every dev machine | Adds a yearly cert rotation and a private key to protect, for a problem the API key already solves. Reserve it for ephemeral CI where the archive-step dev-cert cap bites |

## Quick diagnosis

```bash
# Is the key in place?
ls -l ~/private_keys/AuthKey_<KEY_ID>.p8

# Local distribution identities? (usually NONE, and that's correct)
security find-identity -v -p codesigning | grep -E "Apple Distribution|iPhone Distribution"

# Which cert signed the last export?
/usr/libexec/PlistBuddy -c Print /tmp/AppExport/DistributionSummary.plist | grep -m1 type
# → "Cloud Managed Apple Distribution"
```
