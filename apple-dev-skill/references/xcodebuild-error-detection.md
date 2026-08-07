# xcodebuild Error Detection

## Problem

xcodebuild incremental builds can return **exit code 0** even when a source file has a compile error — if derived data already contains a valid product from a previous successful build. This means checking only `PIPESTATUS[0]` is insufficient.

## Required Pattern

Every xcodebuild wrapper script must verify the result three ways — exit code, failure marker, and *presence* of the success marker:

```bash
xcodebuild build ... 2>&1 | tee /tmp/xc-build.log | grep -E "error:|\*\*" || true

EXIT=${PIPESTATUS[0]}
if [ $EXIT -ne 0 ] \
   || grep -qF "** BUILD FAILED **" /tmp/xc-build.log \
   || ! grep -qF "** BUILD SUCCEEDED **" /tmp/xc-build.log; then
  echo "BUILD FAILED"
  exit 1
fi
```

All three conditions are necessary:
- `PIPESTATUS[0]` catches most failures
- `grep BUILD FAILED` catches incremental build edge cases where exit code is 0
- A missing `BUILD SUCCEEDED` marker catches the case neither of the others can: a build that dies before compiling anything (missing scheme, locked DerivedData, bad destination) writes no failure line either, so a check that only greps for failure lets it through

Name the log after the working directory (`"${TMPDIR:-/tmp/}$(basename "$PWD")-build.log"`) rather than a fixed `/tmp` path. Parallel builds in sibling git worktrees otherwise overwrite each other's logs, and the verification greps then read the wrong build's result.

## Consistency Rule

All `xc-*.sh` scripts (`xc-build.sh`, `xc-build-run.sh`, `xc-test.sh`) must share the same error detection logic. When updating one, audit all others. A script that only checks exit code will eventually let a broken build through — especially during rapid iteration with `xc-build-run.sh` where the focus is on launching, not verifying.

## Also Include

- `CODE_SIGNING_ALLOWED=NO` — prevents signing errors from masking real build failures in CI and local scripts. **Compile-check targets only — never on a build that gets installed** (`simctl install`, run targets, and test targets, whose bundle is installed too). The flag skips the `CodeSign` build phase and leaves only the ad-hoc signature the linker emits; `codesign -dvvv` reports `flags=0x20002(adhoc,linker-signed)` with it versus `flags=0x2(adhoc)` without. Simulator securityd rejects every Keychain call from a linker-signed-only binary with `-34018 errSecMissingEntitlement`: token loads return nil ("not connected" despite a valid stored session) and saves fail silently after a successful OAuth exchange. Simulator ad-hoc signing needs no identity or account — there is no reason to disable it on an installable build. Note that simulator apps carry an empty entitlements dictionary whether or not the flag is used, so do not diagnose this by grepping for `application-identifier`; compare `codesign -dvvv` flags instead.
- Keep the flag consistent across every script sharing one DerivedData path. A flag present in some and absent in others alternates the build-settings fingerprint against a single cache and forces repeated full rebuilds.
- Consistent `XC_CONFIG` — all scripts should source the same `xc-env.sh` for scheme, destination, and configuration

## xcodebuild test: Crash Detection

`xcodebuild test` returns exit 0 with `** TEST SUCCEEDED **` on a
green run and exit non-zero with `** TEST FAILED **` on a failed run —
but **a SIGABRT / EXC_BAD_ACCESS inside the test bundle reports the
same way as an assertion failure**. Grepping only for `error:` or
`failed` will surface assertion misses and **miss every actual crash**.

Required pattern when verifying a test run:

```bash
xcodebuild test ... 2>&1 | tee /tmp/xc-test.log
EXIT=${PIPESTATUS[0]}

# Crashes — the signal that something exploded inside the bundle. Anchor to how
# a crash is REPORTED, not to the signal name: a bare `crashed` matches the host
# app's own runtime logging on this same stream, and a bare `SIGABRT` matches
# Crashlytics printing "The signal SIGABRT has a non-Crashlytics handler" on
# every green run. Grep a known-passing log before widening this.
grep -E "Restarting after unexpected exit|Crashed:|due to (signal )?(SIGABRT|SIGSEGV)|terminated due to" /tmp/xc-test.log

# Plus the usual sanity checks
grep -E "\*\* TEST (SUCCEEDED|FAILED)" /tmp/xc-test.log
```

A test run is only green when **all three** hold:
- exit code is 0
- log contains `** TEST SUCCEEDED **`
- log contains **no** crash marker

**Subtle log-only signature of a crash:** test N prints
`Test Case 'X' started.`, immediately followed by
`Test Case 'Y' started.` with no `passed (Xs)` or `failed (Xs)`
for X in between. That gap is X crashing inside its method body
and the runner moving on without writing a result line. Subsequent
tests may still report `passed` before the bundle finally aborts —
do not trust them.

When in doubt, redirect to a file (`tee /tmp/xc-test.log`) before
grepping. xcodebuild output is voluminous and gets truncated in
terminal multiplexers, so partial logs hide the very lines you need.
