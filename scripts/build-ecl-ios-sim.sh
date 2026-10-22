#!/usr/bin/env bash
# Cross ECL for the iOS simulator on Apple silicon (arm64, iOS $IOS_MIN_VERSION+).
# Needs Xcode (not just CommandLineTools). Output: out/ios-sim-arm64/.
#
# Usage: scripts/build-ecl-ios-sim.sh [--hello]
#   ECL_TO_RUN  host ECL (default out/host/bin/ecl, must match the pin)
#   --hello     also link hello/hello.c (out/ios-sim-arm64/bin/hello-ecl);
#               run it with scripts/run-hello-ios-sim.sh
source "$(dirname "$0")/common.sh"

[[ "$(host_os)" == darwin ]] || die "iOS builds need a macOS host"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)" \
  || die "no iphonesimulator SDK (install Xcode and xcode-select it)"

PREFIX="${OUT}/ios-sim-arm64"
SRC="${WORK}/ios-sim-arm64/ecl"
TRIPLE="arm64-apple-ios${IOS_MIN_VERSION}-simulator"
TARGET_FLAGS="-target ${TRIPLE} -isysroot ${SDK}"

export CC="$(xcrun --sdk iphonesimulator -f clang) ${TARGET_FLAGS}"
export CXX="$(xcrun --sdk iphonesimulator -f clang++) ${TARGET_FLAGS}"
export AR="$(xcrun -f ar)" RANLIB="$(xcrun -f ranlib)"
# Flags from the ECL manual's iOS section ("Building ECL").
export CFLAGS="-O2 -DNO_ASM -DGC_DISABLE_INCREMENTAL -DECL_RWLOCK"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="${TARGET_FLAGS}"
export LIBS="-framework Foundation"
ECL_TO_RUN="$(host_ecl)"
export ECL_TO_RUN

if ! already_built "$PREFIX"; then
  fetch_ecl_src "$SRC"
  cd "$SRC"
  # --build must differ textually from --host or autoconf will try to run target binaries.
  BUILD="$(sh ./src/config.guess)"
  log "configure ${TRIPLE} (build ${BUILD})"
  ./configure --build="$BUILD" --host=aarch64-apple-darwin --prefix="$PREFIX" \
    --disable-shared --disable-c99complex \
    --with-cross-config="${SRC}/src/util/iOS-arm64.cross_config" \
    >"${WORK}/ios-sim-arm64/configure.log" 2>&1 \
    || { tail -50 "${WORK}/ios-sim-arm64/configure.log"; die "configure failed"; }
  make -j"$(ncpu)" >"${WORK}/ios-sim-arm64/make.log" 2>&1 \
    || { tail -80 "${WORK}/ios-sim-arm64/make.log"; die "make failed"; }
  rm -rf "$PREFIX"
  make install >"${WORK}/ios-sim-arm64/install.log" 2>&1
  finish_install "$PREFIX" "ios-sim-arm64-${IOS_MIN_VERSION}" "${TARGET_FLAGS} -framework Foundation"
fi

if [[ "${1:-}" == --hello ]]; then
  mkdir -p "${PREFIX}/bin"
  # shellcheck disable=SC2086
  $CC -O2 "${ROOT}/hello/hello.c" -I"${PREFIX}/include" -L"${PREFIX}/lib" \
    -lecl -leclgc -leclgmp -framework Foundation -o "${PREFIX}/bin/hello-ecl"
  log "hello: $(file -b "${PREFIX}/bin/hello-ecl")"
fi
