# Makefile

Reference template: [Makefile.template](Makefile.template)

The Makefile is the single entry point for building, testing, running, and releasing. Anything a developer or agent must do to this project should be a target — if a workflow needs a README paragraph to explain, it should have been a target instead.

## Design Principles

1. **`help` is the front door** — `.DEFAULT_GOAL := help`; newcomer types `make` and sees every target
2. **One `xc` macro for all xcodebuild calls** — log capture, result verification, and failure diagnostics live in exactly one place
3. **Makefile is the menu; scripts/ is the kitchen** — see [Recipe or Script](#recipe-or-script)
4. **Comments carry constraints** — an external constraint, a non-obvious failure mode, or a contract with another tool (an exit code a script keys on, a doc to keep in sync), in a sentence or two. Section banners that repeat the `echo` below them, provenance ("modeled on …", commit hashes, dates), and restatements of the code are deleted
5. **Self-documenting** — `##` comments extracted by `awk` in `help`
6. **Version management** — `bump VERSION=x.y` and `bump-build`; detect source (shared `Version.xcconfig` vs Project.swift)
7. **Close Xcode before regeneration** — AppleScript closes only workspaces under this repo's path
8. **Complete `.PHONY`** — every non-file target listed; a target name that collides with a same-named file on disk makes `make` treat the file as already up to date and silently skip the recipe otherwise

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
-include Makefile.local

SIM_NAME ?= iPad mini (A17 Pro)
SIM_OS   ?= 26.4
SIM      := platform=iOS Simulator,name=$(SIM_NAME),OS=$(SIM_OS)

SIM_UDID_SH := xcrun simctl list devices available | awk -v n='$(SIM_NAME) (' \
  '/^-- /{f = ($$0 == "-- iOS $(SIM_OS) --"); next} \
   f {l = $$0; sub(/^ +/, "", l); if (index(l, n) == 1) {split(substr(l, length(n) + 1), p, ")"); u[++c] = p[1]}} \
   END {if (c == 1) {print u[1]; exit} \
        print "❌ simulator \047$(SIM_NAME)\047 (iOS $(SIM_OS)): " (c ? c " match, keep one" : "not found, create it in Xcode > Devices") > "/dev/stderr"; exit 1}'
```

`SIM_UDID_SH` prints a UDID only when exactly one device matches; otherwise it exits 1 with the reason on stderr. Three details carry that:

- Scope to the `-- iOS $(SIM_OS) --` section, or a same-named device under another runtime can win.
- Match the line prefix `<SIM_NAME> (`, not a substring — a substring also matches `My iPad mini (A17 Pro)` and `iPad mini (A17 Pro) L10n`.
- Count the matches instead of taking `head -1`, which silently picks one of two same-named devices.

Inside `:=`, write `$$0` so awk receives `$0`. Consume it as `UDID=$$($(SIM_UDID_SH)) || exit 1`, and expose it as a `sim-udid` target (`@$(SIM_UDID_SH)`) so tools outside make — a log reader, a UI driver's `--device` — resolve the same simulator.

`?=` plus the gitignored `-include Makefile.local` lets one checkout, typically a git worktree run in parallel, pin its own simulator without touching the tracked file.

**Never target `booted` for install or launch.** It resolves to whichever simulator happens to be up — an iPhone sim booted from another project makes an iPad-only app fail to install, with an error that names the app rather than the device. Resolve the UDID explicitly and boot it yourself:

```makefile
	UDID=$$($(SIM_UDID_SH)) || exit 1; \
	xcrun simctl bootstatus "$$UDID" -b >/dev/null 2>&1 || { \
	  echo "❌ failed to boot '$(SIM_NAME)' ($$UDID)"; exit 1; }
```

`simctl bootstatus -b` boots when shut down and waits until the device is actually ready; plain `simctl boot` returns before the system finishes launching, and an install issued in that window fails intermittently.

When generating a Makefile that pins a simulator, **ask the user which device and OS version to target**. List real options with `xcrun simctl list devices available`.

**Pin an existing simulator by default rather than creating one per checkout.** The alternative — make creates `<App>-<worktree>` on first use, takes the newest runtime when it cannot ask, and offers an orphan cleanup — makes worktrees self-contained, at three costs. A newly created or erased simulator starts from stock state, losing per-device customisation such as a trimmed daemon profile (one iPad mini ran at 975 MB slimmed against 4.49 GB stock). "Newest runtime" changes the OS under the project the day a runtime installs, which is the drift pinning exists to prevent. Orphan cleanup deletes simulators by name. Auto-create fits when worktrees are many and short-lived and no simulator carries per-device state.

### Physical device selection

A device run needs a resolved UDID before it builds, installs, and launches. Ready-made: [device-udid.sh](device-udid.sh) — copy it to `scripts/` and call it as `DEVICE_TYPE=iPad bash scripts/device-udid.sh`. Stdout carries only the UDID and every message goes to stderr, so `$(make -s device-udid)` composes the way `sim-udid` does.

**Read devices from `xcrun devicectl list devices --json-output <file>`, never from `xcrun xctrace list devices` text.** `devicectl --help` names the JSON file its only supported machine interface. The text has two traps that no line-shape filter avoids: the range `/== Devices ==/,/== Simulators ==/` also spans `== Devices Offline ==`, and a Mac whose name macOS de-duplicated (`… MacBook Air (2)`) gains a second paren group and passes an `(OS) (UDID)` shape test. With one iPad connected, that filter returned six candidates. Filter the JSON by field:

- `.hardwareProperties.deviceType` — `iPhone`, `iPad`
- `.connectionProperties.tunnelState` — `connected`; `disconnected` (paired, reachable on demand); `unavailable`
- `.hardwareProperties.udid` — the id `xcodebuild -destination id=` and `devicectl --device` take, 25 characters (`00008112-001221100E08C01E`). Not `.identifier`, the CoreDevice id, which differs.

Keep network-paired devices: one with `transportType` `localNetwork` installs over Wi-Fi.

**Selection fails closed**, because the caller installs onto and terminates an app on whatever device it returns:

1. An explicit `DEVICE_UDID` must name a paired device of the type in state `connected` or `disconnected`, else exit 1 listing the candidates. Never fall through to a probe: a typo, or a pinned device that left, would silently run on a different one.
2. Without it, exactly one `connected` device auto-selects.
3. Zero or several exit 1 with the candidate list and the `DEVICE_UDID=<UDID>` that picks one.

Never prompt. A `read` without a TTY hangs agents and CI until timeout, with no output saying why; the failure message with candidates is the menu. When a device should stay pinned, set `DEVICE_UDID := <UDID>` in the gitignored `Makefile.local` — scripts read it and never write it. A cache file the script rewrites is the alternative; a project that keeps one must keep it out of version control, since it holds one machine's devices and churns, and must treat a stale entry as an error rather than re-probe and switch devices.

**Build what you install with `-destination id=<UDID>`; keep `generic/platform=iOS` for the no-device compile check.** Both write `Products/<Config>-iphoneos`, but `id=` turns on `ONLY_ACTIVE_ARCH` and `BUILD_ACTIVE_RESOURCES_ONLY` and adds `TARGET_DEVICE_*` and `ASSETCATALOG_FILTER_FOR_DEVICE_MODEL` — it is what the IDE builds with that device selected.

A UDID resolved in the shell cannot reach the `xc` macro, which single-quotes `-destination '$(…)'`. Resolve and validate in the public target, then re-enter make with the UDID as a make variable — this also rejects a bad device before any build starts:

```makefile
DEVICE := id=$(DEVICE_UDID)

run-device:
	@UDID=$$(DEVICE_TYPE='$(DEVICE_TYPE)' DEVICE_UDID='$(DEVICE_UDID)' bash scripts/device-udid.sh) || exit 1; \
	$(MAKE) --no-print-directory run-device-on DEVICE_UDID=$$UDID

build-device-on:
	$(call xc,run-device,$(SCHEME),build,-configuration $(CONFIG) -allowProvisioningUpdates,$(DEVICE))
```

`run-device-on` (depending on `build-device-on`) then reads the product path from build settings for `$(DEVICE)` and platform `iphoneos` (see [Run Target](#run-target)), and installs and launches with `devicectl`, which needs no third-party tooling:

```sh
xcrun devicectl device install app --quiet --device "$UDID" "$APP"
xcrun devicectl device process launch --quiet --terminate-existing --device "$UDID" "$BID" -- $LAUNCH_ARGS
```

App arguments go after `--`; without it devicectl parses an app flag such as `-AppleLanguages` as its own option.

Pass `-allowProvisioningUpdates` on device builds so automatic signing can create or refresh the development profile instead of failing on a stale one. It changes no build setting — `-showBuildSettings` is identical with and without it — so it is safe under the shared-DerivedData flag rule. Registering a device the team has never seen is a separate flag, `-allowProvisioningDeviceRegistration`, which takes effect only alongside it. Once the Mac has Xcode signed in to the team and the device is paired and in Developer Mode, signing needs no TTY (`make run-device </dev/null` signs with the Apple Development identity, no keychain prompt); state those prerequisites in the Makefile for a new machine's first run.

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

## Toolchain Pin

Commit the exact Xcode version the project builds with to `.xcode-version` (e.g. `26.4`, the file `xcodes` also reads) and fail every xcodebuild call when the selected Xcode differs. A mismatched toolchain otherwise fails much later, as opaque compile, macro, or signing errors that look like project bugs. [Makefile.template](Makefile.template) runs the check at the top of the `xc` macro, with `SKIP_XCODE_CHECK=1` as the deliberate override while evaluating a new Xcode (then follow xcconfig.md → Xcode Upgrade SOP and bump the file).

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
# $(5) destination (default: $(SIM))
define xc
	@mkdir -p $(LOGDIR); \
	LOG=$(LOGDIR)/$(1).log; \
	echo "⏳ xcodebuild $(or $(3),test) [$(2)] … (full log: $$LOG)"; \
	set -o pipefail; \
	xcodebuild \
	  -workspace $(WORKSPACE) \
	  -scheme $(2) \
	  -destination '$(or $(5),$(SIM))' \
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

Usage: `$(call xc,dingkit,DingKit)` for tests, `$(call xc,build-debug,DingPOS,build,-configuration Debug)` for a build, and `$(call xc,build-device,DingPOS,build,-configuration Debug -allowProvisioningUpdates,generic/platform=iOS)` for another destination. The destination is a make value inside single quotes, so a UDID resolved in the shell reaches it only through a sub-make (see [Physical device selection](#physical-device-selection)).

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

**Never hardcode the bundle ID or the product path.** Debug builds often append `.debug` to the identifier, and the product directory changes with configuration and platform. Ask xcodebuild for the path, then read the identifier from the built bundle:

```sh
SETTINGS=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -destination "$DESTINATION" -derivedDataPath "$DD" -configuration "$CONFIGURATION" \
    -showBuildSettings -json 2>/dev/null)
APP_PATH=$(printf '%s' "$SETTINGS" | jq -er --arg p iphonesimulator '[.[].buildSettings
    | select(.PRODUCT_TYPE == "com.apple.product-type.application" and .PLATFORM_NAME == $p)]
    | select(length == 1) | .[0] | .TARGET_BUILD_DIR + "/" + .WRAPPER_NAME')
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")
```

Two things make this query return the wrong path when done the obvious way:

- **Pass the build's own destination, `-derivedDataPath`, and configuration.** `TARGET_BUILD_DIR` derives from all three, so querying with `generic/platform=iOS` returns the `iphoneos` directory of a simulator build, and omitting `-derivedDataPath` returns the IDE's DerivedData instead of the one the build wrote to.
- **Select the app's entry, not the first.** `-showBuildSettings` lists one entry per target in the scheme's build action — frameworks, extensions, an embedded watch app — often before the app, so the first `TARGET_BUILD_DIR` / `WRAPPER_NAME` can be a `.framework` or `.appex` the install rejects. Match `PRODUCT_TYPE` = application *and* `PLATFORM_NAME` = the destination's platform (`iphonesimulator`, `iphoneos`), because a modern watch app is also an application, and require exactly one so a scheme that builds two apps fails by name. `-json` makes the entries structured; parsing the text output needs per-block state to get the same answer.

The bundle identifier comes from the built `Info.plist` rather than `PRODUCT_BUNDLE_IDENTIFIER`: it is what `simctl launch` matches against, and it is unambiguous once the path is.

**`print()` output.** A plain `simctl launch` returns immediately and the app's stdout goes nowhere an agent can read. `simctl launch --console-pty` blocks and streams the app's stdout and stderr through a pseudo-terminal, and forwards Ctrl-C to the app. Prefer it over `--stdout=<file>`: on a file, stdout is block-buffered, so `print()` lines arrive late or only at exit, while a pty keeps them line-buffered. An agent runs the blocking launch in the background with its output redirected to a log. [Makefile.template](Makefile.template)'s `run` takes `CONSOLE=1` for this.

Guard the artifact before using it — `[ ! -d "$APP_PATH" ]`. If the build produced nothing at the expected path, reading `Info.plist` fails with a cryptic error that hides the real cause; an explicit check names it.

[Makefile.template](Makefile.template) wraps the query in an `app_settings` macro taking destination and platform, which `run` and `run-device-on` share.

**Per-launch language: `LPROJ=<id>` → `-AppleLanguages "(<id>)"`** after the bundle id (after `--` for devicectl). A launch argument lands in the argument domain, which outranks the app's stored preference for that launch only, so the next plain `run` is back in the configured language and no setting was written. Validate the id against where the strings actually live — the app root's `<id>.lproj`, or `<Package>_<Target>.bundle/<id>.lproj` when an SPM package holds them — and list the available ids on failure; an unknown id otherwise falls back to another language with no error.

**Show the pinned simulator's window:** `open -g -a Simulator --args -CurrentDeviceUDID "$UDID"`. This takes effect when the command launches Simulator; whether it switches windows when Simulator is already running is unverified.

**The build that `run` installs must stay signed** — never pass `CODE_SIGNING_ALLOWED=NO` on it. That flag skips the `CodeSign` build phase, leaving only the ad-hoc signature the linker emits. `codesign -dvvv` tells the two apart: `flags=0x20002(adhoc,linker-signed)` with the flag, `flags=0x2(adhoc)` without it. Simulator securityd rejects every Keychain call from a linker-signed-only binary with `-34018`, so stored credentials read back as nil and new writes fail silently — the app surfaces nothing, and the symptom usually gets misread as an OAuth or session bug. Simulator ad-hoc signing needs no identity or account, so the flag buys nothing here; reserve it for compile-check targets whose product is never installed.

Do not verify this by looking for an `application-identifier` entitlement. Simulator builds carry an empty entitlements dictionary either way — measured across three separate apps — so its absence proves nothing. The real signature is the distinguishing factor; check `codesign -dvvv` flags.

### Landscape-only apps: device vs window orientation

Simulator keeps two rotations per simulator: the device's orientation, which the app sees, and Simulator.app's window rotation, stored in `com.apple.iphonesimulator` under `DevicePreferences.<UDID>.SimulatorWindowOrientation`. Rotation from outside the GUI, such as `sim-use ios rotate`, turns only the device. When the window disagrees, the human watching sees the app sideways or upside down while UI-tree reads and screenshots, which come from the framebuffer, look correct, so an agent never notices.

- The window value names a device orientation: a landscape-right interface needs `LandscapeLeft`.
- The fix is Device ▸ Orientation ▸ Landscape Left on that simulator's window, which is absolute and sets the device too. The menu acts on the key window and is disabled unless Simulator is the active app, so a script (its own `.applescript`, per [Recipe or Script](#recipe-or-script)) activates Simulator, raises the window whose title starts with `<SIM_NAME>` and ends with `iOS <SIM_OS>`, clicks, and hands focus back.
- Read the pref first and touch the GUI only when it differs, so a run that is already aligned never steals focus: `defaults export com.apple.iphonesimulator - | plutil -extract "DevicePreferences.$UDID.SimulatorWindowOrientation" raw -o - -`.

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

- [ ] Target device: simulator (pin name + OS, ask the user; `Makefile.local` for per-checkout overrides), physical (`device-udid.sh` with `DEVICE_TYPE`, first-run signing prerequisites stated), or both
- [ ] Landscape-only app: `run` aligns the Simulator window with the device orientation
- [ ] DerivedData: project-local or shared with IDE — and are the CLI flags consistent with that choice?
- [ ] Version source: one `Version.xcconfig` every app and extension target includes, or Project.swift
- [ ] Toolchain pin: `.xcode-version` committed and matching the team's Xcode
- [ ] Test structure: Xcode scheme tests, SPM package tests, or both; which scopes deserve a named target vs `ONLY=`
- [ ] Generator: Tuist → `install` / `generate` / `open`; none → skip
- [ ] Release flow: App Store → delegate to `scripts/release.sh`; framework → tag only
- [ ] Project-specific tooling (codegen, fixtures, linting, UI smoke suite)
