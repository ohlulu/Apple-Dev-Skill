#!/usr/bin/env bash
# Print the UDID of the physical device to run on; every message goes to stderr.
# Usage: DEVICE_TYPE=iPhone|iPad [DEVICE_UDID=<udid>] bash scripts/device-udid.sh
#
# DEVICE_UDID must name a paired, reachable device of DEVICE_TYPE; without it the one
# connected device of that type is used. Anything else lists the candidates and exits 1:
# the caller installs onto and terminates an app, so it never guesses a device.
# devicectl's JSON file is its only supported machine interface; `xctrace list devices`
# text also lists the host Mac and offline devices.
set -euo pipefail

TYPE=${DEVICE_TYPE:-}
if [ -z "$TYPE" ]; then
  echo "❌ DEVICE_TYPE is unset (devicectl hardwareProperties.deviceType: iPhone, iPad)" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "❌ jq not installed (brew install jq)" >&2; exit 2; }

JSON=$(mktemp)
trap 'rm -f "$JSON"' EXIT

if ! xcrun devicectl list devices --quiet --json-output "$JSON" >/dev/null 2>&1; then
  echo "❌ xcrun devicectl list devices failed" >&2
  exit 1
fi

DEVICES=$(jq -r --arg t "$TYPE" '.result.devices[]
  | select(.hardwareProperties.deviceType == $t)
  | [.hardwareProperties.udid, .connectionProperties.tunnelState, .deviceProperties.name]
  | @tsv' "$JSON") || { echo "❌ unexpected devicectl JSON in $JSON" >&2; exit 1; }

list_devices() {
  if [ -z "$DEVICES" ]; then
    echo "   (no paired $TYPE — pair one in Xcode > Devices and Simulators)" >&2
  else
    printf '%s\n' "$DEVICES" | awk -F'\t' '{ printf "   %s  %s (%s)\n", $1, $3, $2 }' >&2
  fi
}

if [ -n "${DEVICE_UDID:-}" ]; then
  # `disconnected` = paired and reachable on demand; `unavailable` = out of reach.
  ROW=$(printf '%s\n' "$DEVICES" | awk -F'\t' -v u="$DEVICE_UDID" '$1 == u')
  STATE=$(printf '%s' "$ROW" | cut -f2)
  if [ -z "$ROW" ] || { [ "$STATE" != connected ] && [ "$STATE" != disconnected ]; }; then
    echo "❌ DEVICE_UDID=$DEVICE_UDID is not a reachable paired $TYPE. Paired:" >&2
    list_devices
    exit 1
  fi
else
  ROW=$(printf '%s\n' "$DEVICES" | awk -F'\t' '$2 == "connected"')
  COUNT=$(printf '%s' "$ROW" | grep -c . || true)
  if [ "$COUNT" -ne 1 ]; then
    if [ "$COUNT" -eq 0 ]; then
      echo "❌ no connected $TYPE (unlock it, or pick one with DEVICE_UDID=<UDID>). Paired:" >&2
    else
      echo "❌ $COUNT connected ${TYPE}s — pick one with DEVICE_UDID=<UDID>:" >&2
    fi
    list_devices
    exit 1
  fi
fi

printf '%s\n' "$ROW" | awk -F'\t' '{ printf "📱 %s (%s)\n", $3, $2 }' >&2
printf '%s\n' "$ROW" | cut -f1
