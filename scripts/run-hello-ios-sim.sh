#!/usr/bin/env bash
# Boot an iPhone simulator (if none is booted) and run the hello binary in it
# with `simctl spawn`. Prints the binary's stdout.
#
# Usage: scripts/run-hello-ios-sim.sh [binary]
source "$(dirname "$0")/common.sh"

BIN="${1:-${OUT}/ios-sim-arm64/bin/hello-ecl}"
[[ -x "$BIN" ]] || die "no binary at $BIN (build-ecl-ios-sim.sh --hello)"

udid="$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        print(d["udid"]); sys.exit()')"
if [[ -z "$udid" ]]; then
  udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
for rt, devs in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    if "iOS" not in rt: continue
    for d in devs:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit()')"
  [[ -n "$udid" ]] || die "no available iPhone simulator"
  log "booting simulator $udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
fi
log "simctl spawn $udid $BIN"
xcrun simctl spawn "$udid" "$BIN"
