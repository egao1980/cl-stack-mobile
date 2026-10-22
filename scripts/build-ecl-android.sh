#!/usr/bin/env bash
# Cross ECL for android/arm64 (API $ANDROID_API, NDK $NDK_VERSION+, 16 KB pages).
# Output: out/android-arm64/{lib/libecl.a,include,target-info.lisp,build-info.txt}.
#
# Usage: scripts/build-ecl-android.sh [--hello]
#   NDK lookup: $ANDROID_HOME/ndk/$NDK_REVISION, then $ANDROID_NDK_ROOT (r27+), else
#               fetch $NDK_VERSION into the cache
#   ECL_TO_RUN        host ECL (default out/host/bin/ecl, must match the pin)
#   --hello           also link hello/hello.c as a static executable (out/android-arm64/bin/hello-ecl)
source "$(dirname "$0")/common.sh"

PREFIX="${OUT}/android-arm64"
SRC="${WORK}/android-arm64/ecl"
source "$(dirname "$0")/android-env.sh"

ECL_TO_RUN="$(host_ecl)"
export ECL_TO_RUN

if ! already_built "$PREFIX"; then
  fetch_ecl_src "$SRC"
  cd "$SRC"
  log "configure ${TARGET}${ANDROID_API}"
  ./configure --host="$TARGET" --prefix="$PREFIX" \
    --disable-shared --disable-c99complex \
    --with-cross-config="${SRC}/src/util/android-arm64.cross_config" \
    >"${WORK}/android-arm64/configure.log" 2>&1 \
    || { tail -50 "${WORK}/android-arm64/configure.log"; die "configure failed"; }
  make -j"$(ncpu)" >"${WORK}/android-arm64/make.log" 2>&1 \
    || { tail -80 "${WORK}/android-arm64/make.log"; die "make failed"; }
  rm -rf "$PREFIX"
  make install >"${WORK}/android-arm64/install.log" 2>&1
  finish_install "$PREFIX" "android-arm64-api${ANDROID_API}" "${PAGE_FLAGS}"
fi

if [[ "${1:-}" == --hello ]]; then
  mkdir -p "${PREFIX}/bin"
  # Bionic refuses executables whose TLS segment is aligned < 64 on arm64
  # (shared libraries loaded by an app are not checked).
  tls_align="${WORK}/android-arm64/tls-align.c"
  echo '__thread char cl_stack_mobile_tls_align[64] __attribute__((aligned(64), used));' > "$tls_align"
  $CC -fno-emulated-tls -c "$tls_align" -o "${tls_align%.c}.o"
  # -static: a bionic static executable runs on any arm64 Linux kernel
  # (docker linux/arm64, qemu-aarch64), so the proof needs no emulator.
  # shellcheck disable=SC2086
  $CC -static -O2 "${ROOT}/hello/hello.c" "${tls_align%.c}.o" -I"${PREFIX}/include" -L"${PREFIX}/lib" \
    -lecl -leclgc -leclgmp -leclatomic -lm ${PAGE_FLAGS} -o "${PREFIX}/bin/hello-ecl"
  log "hello: $(file -b "${PREFIX}/bin/hello-ecl")"
fi
