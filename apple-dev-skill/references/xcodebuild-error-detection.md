# xcodebuild Error Detection

## Problem

xcodebuild incremental builds can return **exit code 0** even when a source file has a compile error — if derived data already contains a valid product from a previous successful build. This means checking only `PIPESTATUS[0]` is insufficient.

## Required Pattern

Every xcodebuild wrapper script must use **dual failure detection**:

```bash
xcodebuild build ... 2>&1 | tee /tmp/xc-build.log | grep -E "error:|\*\*" || true

EXIT=${PIPESTATUS[0]}
if [ $EXIT -ne 0 ] || grep -q "BUILD FAILED" /tmp/xc-build.log; then
  echo "BUILD FAILED"
  exit 1
fi
```

Both conditions are necessary:
- `PIPESTATUS[0]` catches most failures
- `grep BUILD FAILED` catches incremental build edge cases where exit code is 0

## Consistency Rule

All `xc-*.sh` scripts (`xc-build.sh`, `xc-build-run.sh`, `xc-test.sh`) must share the same error detection logic. When updating one, audit all others. A script that only checks exit code will eventually let a broken build through — especially during rapid iteration with `xc-build-run.sh` where the focus is on launching, not verifying.

## Also Include

- `CODE_SIGNING_ALLOWED=NO` — prevents signing errors from masking real build failures in CI and local scripts. **Compile-check and test targets only — never on a build that gets installed** (`simctl install`, run targets). The flag skips even ad-hoc signing, so the binary ships without an `application-identifier` entitlement and simulator securityd rejects every Keychain call with `-34018 errSecMissingEntitlement`: token loads return nil ("not connected" despite a valid stored session) and saves fail silently after a successful OAuth exchange. Simulator ad-hoc signing needs no identity or account — there is no reason to disable it on an installable build.
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

# Crashes — the signal that something exploded inside the bundle
grep -E "Restarting after unexpected exit|crashed|SIGABRT|EXC_BAD_ACCESS" /tmp/xc-test.log

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
