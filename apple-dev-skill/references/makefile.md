# Makefile

Reference template: [Makefile.template](Makefile.template)

The Makefile is the single entry point for building, testing, running, and releasing. Anything a developer or agent must do to this project should be a target — if a workflow needs a README paragraph to explain, it should have been a target instead.

## Design Principles

1. **`help` is the front door** — `.DEFAULT_GOAL := help`; newcomer types `make` and sees every target
2. **One `xc` macro for all xcodebuild calls** — log capture, result verification, and failure diagnostics live in exactly one place
3. **Makefile is the menu; scripts/ is the kitchen** — see [Recipe or Script](#recipe-or-script)
4. **Comments explain WHY** — not what the target name already says
5. **Self-documenting** — `##` comments extracted by `awk` in `help`
6. **Version management** — `bump VERSION=x.y` and `bump-build`; detect source (xcconfig vs Project.swift)
7. **Close Xcode before regeneration** — AppleScript closes only workspaces under this repo's path
8. **Complete `.PHONY`** — every non-file target listed

## Recipe or Script?

Move a recipe into `scripts/` once **any** of these is true:

- More than ~10 lines of shell
- Needs a loop, a function, or nested conditionals
- You would want to run it standalone while debugging it
- It contains AppleScript — put it in its own `.applescript` file and call `osascript scripts/foo.applescript`
- It is invoked by CI as well as by humans

Keep it inline when it is a single command or a short guarded sequence (`clean`, `install`, `open`, `version`).

Shell inside a Makefile pays a permanent tax: `$$` escaping, a trailing backslash on every line, no `shellcheck`, no `sh -x`, and no way to execute one step in isolation. Under ~10 lines that tax is cheaper than a second file; past it, the recipe becomes the hardest code in the repo to debug precisely when it breaks.

Both extremes fail. A Makefile carrying 400 lines of recipes is unmaintainable; a Makefile whose every target is a one-line `sh scripts/x.sh` forces a second file open to answer any question. Target names, `##` docs, and configuration variables stay in the Makefile so `make help` remains the map.

## Target Device: Simulator or Physical

Decide this first — it determines the destination string, the install mechanism, and whether `run` can work unattended.

Some projects **cannot** use the simulator: a binary dependency shipping only an `arm64-iOS` device slice (common with vendored `.framework` bundles from CocoaPods) fails at the simulator link step. When that is the case, state it in the Makefile header with the reason, so nobody re-litigates it every few months:

```makefile
# No simulator support: YYImage's vendored WebP.framework has a device-only
# slice, so simulator builds always fail at link. build uses
# generic/platform=iOS for a pure compile check; run/test need a real device.
```

### Simulator destination

Pin device model **and** OS version, and derive everything else from them. Without both pinned, xcodebuild picks whichever runtime is available, which drifts between machines and after Xcode updates.

```makefile
SIM_NAME := iPad mini (A17 Pro)
SIM_OS   := 26.4
SIM      := platform=iOS Simulator,name=$(SIM_NAME),OS=$(SIM_OS)

# Resolves the pinned sim's UDID. The awk range scopes the search to the
# $(SIM_OS) runtime section — a same-named device registered under a different
# runtime can otherwise win the grep and silently receive the install.
SIM_UDID_SH := xcrun simctl list devices available | awk '/^-- iOS $(SIM_OS) --/{f=1;next} /^--/{f=0} f' | grep -F '$(SIM_NAME) (' | grep -oE '[0-9A-F-]{36}' | head -1
```

Use as `UDID=$$($(SIM_UDID_SH))` inside a recipe; an empty result means the device does not exist.

**Never target `booted` for install or launch.** It resolves to whichever simulator happens to be up — an iPhone sim booted from another project makes an iPad-only app fail to install, with an error that names the app rather than the device. Resolve the UDID explicitly and boot it yourself:

```makefile
	UDID=$$($(SIM_UDID_SH)); \
	if [ -z "$$UDID" ]; then \
	  echo "❌ simulator '$(SIM_NAME)' (iOS $(SIM_OS)) not found — create it in Xcode > Devices"; exit 1; \
	fi; \
	xcrun simctl bootstatus "$$UDID" -b >/dev/null 2>&1 || { \
	  echo "❌ failed to boot '$(SIM_NAME)' ($$UDID)"; exit 1; }
```

`simctl bootstatus -b` boots when shut down and waits until the device is actually ready; plain `simctl boot` returns before the system finishes launching, and an install issued in that window fails intermittently.

When generating a Makefile that pins a simulator, **ask the user which device and OS version to target**. List real options with `xcrun simctl list devices available`.

### Physical device selection

A device-based workflow needs a resolved UDID before every build, install, and test. Put the resolution in one sourceable script and give it a fixed precedence:

1. `DEVICE_UDID=<udid>` in the environment — one-off override
2. A gitignored cache file (`scripts/config`, shell syntax so it can be sourced and hand-edited) — but treat a cached device that is no longer connected as a cache miss
3. Live probe via `xcrun xctrace list devices`

**A device-selection script must never block on `read` in a non-interactive shell.** Agents and CI run without a TTY; a menu prompt there hangs until timeout with no output explaining why. Gate the prompt on `[ -t 0 ]` and make the non-interactive branch fail loudly with the candidate list and the exact command to pick one:

```sh
if [ "$_count" -eq 1 ]; then
    UDID=$(_udid_of "$_devices")          # unambiguous — auto-select, no prompt
elif [ -t 0 ]; then
    ...                                    # interactive menu
else
    echo "❌ Multiple devices detected in a non-interactive environment. Candidates:"
    printf '%s\n' "$_devices" | sed 's/^/   /'
    echo "   Pick and save: make device DEVICE_UDID=<UDID>; or one-off: make run DEVICE_UDID=<UDID>"
    exit 1
fi
```

The same rule applies to any script a Makefile target can reach: **auto-resolve when the answer is unambiguous, prompt only with a TTY, fail with instructions otherwise.**

Filter the device list structurally rather than by name. Every physical iOS device line ends with two parenthesized groups — `(OS version) (UDID)` — while the host Mac has only one, so the shape excludes it without hardcoding anything:

```sh
xcrun xctrace list devices 2>/dev/null \
    | sed -n '/== Devices ==/,/== Simulators ==/p' \
    | grep -E '\([^()]+\) \([0-9A-Fa-f-]+\)[[:space:]]*$'
```

Install and launch on device with `devicectl` (Xcode 15+), which needs no third-party tooling:

```sh
xcrun devicectl device install app --device "$UDID" "$APP_PATH"
xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE_ID"
```

Device builds also need `-allowProvisioningUpdates` so xcodebuild can register the device and refresh the profile instead of failing on a stale one.

## DerivedData Strategy

Two viable strategies, opposite trade-offs. Pick deliberately — the choice constrains which xcodebuild flags you may pass.

| | Project-local (`-derivedDataPath .derivedData`) | Shared with Xcode IDE (omit the flag) |
|---|---|---|
| Best for | Small/medium projects, CI, multiple worktrees | Large projects where a cold build is 10+ minutes |
| Cost | CLI and IDE each keep a full cache; CLI builds start cold | CLI and IDE contend on the same build lock |
| Flag freedom | Any flags — the cache is yours | Flags must match what the IDE passes |
| Warning parity with IDE | Needs a dedicated `warnings` target | Automatic |

**If you share DerivedData with the IDE, CLI flags must not change the build-settings fingerprint.** `-skipMacroValidation` and `CODE_SIGNING_ALLOWED=NO` both do, and each alternating CLI/IDE build then triggers a full rebuild — the exact cost sharing was meant to avoid. Adding such a flag is not a local decision: it forces the project onto local DerivedData.

Sharing also means the two builds serialize on one lock, so a CLI build started while Xcode is compiling simply waits. When that becomes frequent, add an opt-in `DD=` override that switches to a local path while the project keeps sharing by default.

[Makefile.template](Makefile.template) ships project-local, since it is the safer starting point: correct on any project size, and it cannot be broken by a flag change. Switch to sharing when cold-build cost actually hurts.

## Build Result Verification

**Exit code alone is not a reliable success signal.** Three ways a green exit hides a red build:

- An incremental build with stale products in DerivedData can exit 0 despite a compile error
- A test bundle that crashes (`SIGABRT`, `EXC_BAD_ACCESS`) can exit 0 *and* print `TEST SUCCEEDED`
- A build that dies before compiling anything (missing scheme, locked DerivedData) produces a log with no failure line at all — so any check that only greps for failure passes it

Require all three conditions before reporting green: **exit code 0, the success marker present, and no crash marker.** Checking for the *presence* of `** BUILD SUCCEEDED **` is what catches the third case; grepping only for `BUILD FAILED` cannot.

```sh
if grep -qE "$CRASH_PATTERN" "$LOG"; then
    echo "❌ Crash detected in test run. Full log → ${LOG}"
    grep -E "$CRASH_PATTERN" "$LOG" | head -5
    exit 1
fi
if grep -qF "** TEST FAILED **" "$LOG" || ! grep -qF "** TEST SUCCEEDED **" "$LOG"; then
    echo "❌ TEST SUCCEEDED marker missing despite exit 0. Full log → ${LOG}"
    exit 1
fi
```

Anchor the crash pattern to how a crash is *reported*, not to the signal name. A bare `crashed` matches the host app's own runtime logging, which shares the output stream. So does a bare `SIGABRT`: Firebase Crashlytics prints `The signal SIGABRT has a non-Crashlytics handler` on every green run, which reddens the entire suite. Start from markers that only appear on an actual abort — `Restarting after unexpected exit|Crashed:|due to (signal )?(SIGABRT|SIGSEGV)|terminated due to` — and before widening it, grep a known-passing log for the term you are about to add.

This applies to any target that inspects a build log, `warnings` included.

## Streaming Output

Redirecting the whole build to a log file and grepping after it finishes is fine for short runs, but on a long build it shows nothing until the end — including when it has already failed in the first minute. Stream errors live and keep the full log on disk:

```sh
ERROR_PATTERN="error: |BUILD FAILED|TEST FAILED|Testing failed"

set -o pipefail
xcodebuild ... 2>&1 | tee "$LOG" | { grep --line-buffered -E "$ERROR_PATTERN" || true; }
```

- `error: ` keeps the trailing space — a bare `error:` also matches any Objective-C selector carrying an `error:` parameter label, and those appear in ordinary runtime logging on the same stream. `+[CHHapticPattern patternForKey:error:]` alone streams 45 false failures per green iOS test run. Every real diagnostic is `error: <message>`, so the space excludes selectors without dropping anything. Same discipline as `CRASH_PATTERN`: grep a known-passing log before trusting either pattern
- `set -o pipefail` — without it the pipeline reports grep's status and every build looks successful. Requires `SHELL := /bin/bash` in the Makefile
- `--line-buffered` — grep buffers by block when writing to a pipe, so matches arrive in bursts long after the event without it
- `|| true` on the grep so a run with zero matches does not itself fail the pipeline
- `tee` keeps the full log for the failure path to point at

**Avoid `xcbeautify --quieter` for this.** It filters per compilation task, so a task that emits a warning before an error has both suppressed together — in a project with a backlog of warnings, that means failures with no visible cause.

Name log files after the working directory (`$(basename "$PWD")-build.log`) when the repo is used with git worktrees, so parallel builds in sibling checkouts do not overwrite each other's logs.

## The `xc` Macro

One macro centralizes destination, DerivedData, log handling, and result verification for every xcodebuild call. Adding a test target then costs one line and cannot drift from the others.

```makefile
# $(1) log-name  $(2) scheme  $(3) action (default: test)  $(4) extra flags
define xc
	@mkdir -p $(LOGDIR); \
	LOG=$(LOGDIR)/$(1).log; \
	echo "⏳ xcodebuild $(or $(3),test) [$(2)] … (full log: $$LOG)"; \
	set -o pipefail; \
	xcodebuild \
	  -workspace $(WORKSPACE) \
	  -scheme $(2) \
	  -destination '$(SIM)' \
	  -derivedDataPath "$(DD)" \
	  -skipMacroValidation \
	  $(4) \
	  $(or $(3),test) 2>&1 \
	  | tee "$$LOG" \
	  | { grep --line-buffered -E '$(ERROR_PATTERN)' || true; }; \
	RESULT=$$?; \
	if [ $$RESULT -ne 0 ] \
	   || grep -qE '\*\* (BUILD|TEST) FAILED \*\*' "$$LOG" \
	   || ! grep -qE '\*\* (BUILD|TEST) SUCCEEDED \*\*' "$$LOG" \
	   || grep -qE '$(CRASH_PATTERN)' "$$LOG"; then \
	  echo ""; echo "  ❌ full log → $$LOG"; \
	  exit 1; \
	fi
endef
```

Usage: `$(call xc,dingkit,DingKit)` for tests, `$(call xc,build-debug,DingPOS,build,-configuration Debug)` for a build.

## Parameterised Targets

Prefer a parameter over a new target when the variants differ only in a flag value. Six near-identical `test-*` targets cannot express "just this one test", while one parameterised target can:

```makefile
## Unit tests. ONLY="AppTests/LoginTests" narrows scope (space-separated for several).
## CONFIG= selects a configuration (default Debug).
test:
	@CONFIGURATION=$(CONFIG) sh scripts/test.sh $(ONLY)
```

Keep named targets for scopes with real identity — a module's own scheme, or the CI gate that must run everything. `make test-kit` is worth a target; `make test ONLY=...` covers the rest.

Document every parameter in the `##` comment. That comment is the only place users look, since it is what `make help` prints.

## Run Target

Always provide a `run` target that builds, installs, and launches in one command — the single command both agents and developers use, with no manual `simctl` or `devicectl` sequences.

**Never hardcode the bundle ID or the product path.** Debug builds often append `.debug` to the identifier, and the product directory changes with configuration and platform. Ask xcodebuild instead:

```sh
SETTINGS=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -destination generic/platform=iOS -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null)

TARGET_BUILD_DIR=$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ TARGET_BUILD_DIR =/{print $2; exit}')
WRAPPER_NAME=$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ WRAPPER_NAME =/{print $2; exit}')
BUNDLE_ID=$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER =/{print $2; exit}')
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
```

`PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"` is an acceptable shortcut when the path is already known, but `-showBuildSettings` survives configuration changes that a hardcoded `Debug-iphonesimulator` path does not.

Guard the artifact before using it — `[ ! -d "$APP_PATH" ]`. If the build produced nothing at the expected path, reading `Info.plist` fails with a cryptic error that hides the real cause; an explicit check names it.

**The build that `run` installs must stay signed** — never pass `CODE_SIGNING_ALLOWED=NO` on it. That flag skips the `CodeSign` build phase, leaving only the ad-hoc signature the linker emits. `codesign -dvvv` tells the two apart: `flags=0x20002(adhoc,linker-signed)` with the flag, `flags=0x2(adhoc)` without it. Simulator securityd rejects every Keychain call from a linker-signed-only binary with `-34018`, so stored credentials read back as nil and new writes fail silently — the app surfaces nothing, and the symptom usually gets misread as an OAuth or session bug. Simulator ad-hoc signing needs no identity or account, so the flag buys nothing here; reserve it for compile-check targets whose product is never installed.

Do not verify this by looking for an `application-identifier` entitlement. Simulator builds carry an empty entitlements dictionary either way — measured across three separate apps — so its absence proves nothing. The real signature is the distinguishing factor; check `codesign -dvvv` flags.

## Warnings Target

Needed only under the project-local DerivedData strategy. When CLI and IDE share DerivedData they see the same diagnostics and a plain clean build suffices.

With separate caches, the `xc` macro's log redirection hides warnings and the two incremental caches disagree — the CLI can report 0 warnings while Xcode shows dozens. A dedicated target clean-builds against Xcode's DerivedData:

```makefile
# Xcode IDE DerivedData for this exact workspace. Match on the WorkspacePath
# recorded in each candidate's info.plist — see below for why a name glob isn't enough.
XCODE_DD = $(shell for d in ~/Library/Developer/Xcode/DerivedData/$(basename $(WORKSPACE))-*; do \
	  [ "$$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$$d/info.plist" 2>/dev/null)" = "$(REPO_ROOT)/$(WORKSPACE)" ] && echo "$$d" && break; \
	done)

## Show Swift warnings (clean build against Xcode's DerivedData, for IDE parity)
warnings:
	@if [ -z "$(XCODE_DD)" ]; then \
	  echo "⚠️  No Xcode DerivedData found. Open the project in Xcode first."; \
	  exit 1; \
	fi; \
	mkdir -p $(LOGDIR); \
	echo "⏳ clean build (Xcode DerivedData) …"; \
	xcodebuild clean build \
	  -workspace $(WORKSPACE) -scheme $(SCHEME) \
	  -destination '$(SIM)' -derivedDataPath "$(XCODE_DD)" \
	  -configuration Debug \
	  > $(LOGDIR)/warnings.log 2>&1; \
	BUILD_EXIT=$$?; \
	if [ $$BUILD_EXIT -ne 0 ] \
	   || grep -qF '** BUILD FAILED **' $(LOGDIR)/warnings.log \
	   || ! grep -qF '** BUILD SUCCEEDED **' $(LOGDIR)/warnings.log; then \
	  echo ""; echo "❌  BUILD FAILED — full log → $(LOGDIR)/warnings.log"; \
	  exit 1; \
	fi; \
	grep 'warning:' $(LOGDIR)/warnings.log | grep -v 'appintentsmetadata\|libtool' | sort -u; \
	COUNT=$$(grep 'warning:' $(LOGDIR)/warnings.log | grep -v 'appintentsmetadata\|libtool' | wc -l | tr -d ' '); \
	echo ""; echo "✅  $$COUNT warning(s)"
```

Clean build is essential — incremental builds cache stale diagnostics and report 0 warnings even when issues exist. Adjust the `grep -v` noise filter for the project's own non-actionable warnings. The success-marker check matters here more than anywhere: a failed build produces a log with no `warning:` lines, and without it the target prints a triumphant `✅ 0 warning(s)`.

**Resolve the IDE's DerivedData by workspace path, never by `-name '<project>-*' | head -1`.** The directory suffix is a hash of the workspace's absolute path, so a new directory appears for every location the project has occupied — git worktrees, a `/tmp` clone made for a baseline comparison, a repo that moved. A real machine had four `DingPOS-*` directories, two of them pointing at `/tmp` checkouts. `head -1` returns whichever the filesystem lists first, so the target silently clean-builds a stale copy and reports another checkout's warnings. Each directory's `info.plist` records its `WorkspacePath`; comparing against it is deterministic and degrades to empty when nothing matches, which the `[ -z ... ]` guard already handles.

## Clean & Destructive Ops

Never `rm -rf $(VAR)` in a Makefile. A misspelled or empty variable turns `rm -rf $(DD)` into `rm -rf` (current directory contents on some shells) or worse, `rm -rf /` if a path is mis-joined. The blast radius is asymmetric: you save zero seconds when it works, lose everything when it doesn't.

Use `trash` (recoverable) and guard each path:

```makefile
## Remove DerivedData, Tuist cache, and test logs
clean:
	@[ -d "$(DD)" ] && trash "$(DD)" && echo "  trashed $(DD)" || true
	@[ -d "$(LOGDIR)" ] && trash "$(LOGDIR)" && echo "  trashed $(LOGDIR)" || true
	@tuist clean 2>/dev/null || true
	@echo "✅  clean."
```

Why this shape:
- `[ -d "$(DD)" ]` — only delete when the path exists *and* is a directory; protects against empty variables
- Quoted `"$(DD)"` — spaces in paths don't split into stray arguments
- `trash` instead of `rm -rf` — mistakes go to Finder Trash, not the void. Install with `brew install trash`
- `tuist clean 2>/dev/null || true` — don't fail the target when Tuist isn't installed or has nothing to clean

Nesting `LOGDIR` inside `DD` lets one guarded `trash` sweep both and keeps the repo root uncluttered.

## Tuist Companion Targets

When `tuist generate` is part of the workflow, three small targets pay for themselves:

```makefile
## Resolve and fetch SPM dependencies
install:
	tuist install

## Close Xcode window and regenerate project
generate gen:
	@osascript scripts/xcode-close.applescript "$(REPO_ROOT)/" 2>/dev/null || true
	tuist generate

## Regenerate workspace and open in Xcode
open: generate
	@open $(WORKSPACE)
```

- `install` — explicit SPM resolve step. Newcomers run it after clone; CI runs it before generating
- `open` — regenerate and open in one command, so an agent can leave the IDE warm for the developer after a structural change
- `gen` — muscle-memory alias. Declare as `generate gen:` so both names share one recipe, and keep the `help` awk multi-target-aware (see Help Target) or the alias silently drops out of the menu

Regeneration must close the project's Xcode window first — Xcode holds references to the old project file and shows phantom errors afterwards. Ready-made: [xcode-close.applescript](xcode-close.applescript), which takes the repo root and closes only workspaces under it.

**Match the window by file path, not by title.** Title-prefix matching also closes projects that merely share a prefix (`MyApp` matches `MyAppTweak`), and it cannot distinguish two checkouts of the same repo. Keep the AppleScript in its own file too — as a Make variable assembled from a dozen `-e` fragments it is unreadable and every `$` needs escaping.

## Help Target

`help` extracts each `##` comment and the target name that follows it. Three awk details are easy to get wrong:

- **Strip the trailing colon** — run `sub(/:.*/,"",$$1)` before printing. Awk field `$$1` on a line like `build:` is the whole token including the colon; without the strip every entry renders as `build:`
- **Match multi-target lines** — use `/^[a-zA-Z0-9_-]+( [a-zA-Z0-9_-]+)*:/`. A single-token regex (`^[a-zA-Z_-]+:`) silently drops any line declaring more than one target, so aliases like `generate gen:` never appear
- **Do not let a plain `#` comment clear the pending description** — add `/^#/{next}` before the target rule. The naive final clause `!/^##/{d=""}` resets `d` on *any* non-`##` line, so the common shape of a `##` doc line followed by a `#` comment explaining the why, then the target, drops that target from the menu entirely. This one hides well: the target still works, it is just invisible in `make help`

```makefile
## Show available targets
help:
	@awk '/^##/{if(!d){sub(/^## ?/,"");d=$$0};next} /^#/{next} /^[a-zA-Z0-9_-]+( [a-zA-Z0-9_-]+)*:/{if(d){sub(/:.*/,"",$$1);printf "  \033[36m%-16s\033[0m %s\n",$$1,d};d=""} {d=""}' $(MAKEFILE_LIST)
```

## Adaptation Checklist

- [ ] Target device: simulator (pin name + OS, ask the user) or physical (selection script with cache + non-interactive failure)
- [ ] DerivedData: project-local or shared with IDE — and are the CLI flags consistent with that choice?
- [ ] Result verification: exit code + success marker + crash marker, in every target that reads a build log
- [ ] Version source: xcconfig (`MARKETING_VERSION`) or Project.swift
- [ ] Test structure: Xcode scheme tests, SPM package tests, or both; which scopes deserve a named target vs `ONLY=`
- [ ] Generator: Tuist → `install` / `generate` / `open`; none → skip
- [ ] Release flow: App Store → delegate to `scripts/release.sh`; framework → tag only
- [ ] Recipes over ~10 lines or containing AppleScript → moved to `scripts/`
- [ ] Project-specific tooling (codegen, fixtures, linting, UI smoke suite)
