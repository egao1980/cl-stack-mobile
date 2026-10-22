#!/usr/bin/env bash
# Run a target's hello-ecl and assert it prints the pinned ECL version.
#
# Usage: scripts/verify-hello.sh host|wasm32|android-arm64|ios-sim-arm64
#   android-arm64 runs the static bionic binary natively on arm64 Linux, else
#   under qemu-aarch64(-static), else in docker --platform linux/arm64; and
#   checks every LOAD segment is 16 KB aligned.
source "$(dirname "$0")/common.sh"

target="${1:?target}"

case "$target" in
  host)
    cfg="${OUT}/host/bin/ecl-config"
    # shellcheck disable=SC2046
    cc "${ROOT}/hello/hello.c" $("$cfg" --cflags) $("$cfg" --ldflags) -o "${WORK}/hello-host"
    out="$("${WORK}/hello-host")" ;;
  wasm32)
    out="$(node "${OUT}/wasm32/hello/hello.js")" ;;
  android-arm64)
    bin="${OUT}/android-arm64/bin/hello-ecl"
    readelf="$(command -v llvm-readelf || command -v readelf || true)"
    if [[ -n "$readelf" ]]; then
      bad="$("$readelf" -lW "$bin" | awk '$1 == "LOAD" && $NF != "0x4000"')"
      [[ -z "$bad" ]] || die "LOAD segments not 16 KB aligned:\n$bad"
      log "android-arm64: all LOAD segments 16 KB aligned"
    fi
    out="$(run_android "$bin")" ;;
  ios-sim-arm64)
    out="$("${ROOT}/scripts/run-hello-ios-sim.sh")" ;;
  *) die "unknown target $target" ;;
esac

echo "$out"
grep -q "hello-ecl: ECL ${ECL_VERSION}" <<<"$out" || die "${target}: expected 'hello-ecl: ECL ${ECL_VERSION}'"
log "${target}: ok"
