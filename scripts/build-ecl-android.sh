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

TARGET=aarch64-linux-android
PREFIX="${OUT}/android-arm64"
SRC="${WORK}/android-arm64/ecl"
# Play requires 16 KB-aligned ELF segments (Android 15+); r28+ defaults to it, r27 does not.
PAGE_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"

ndk_major() { sed -n 's/^Pkg.Revision *= *\([0-9]*\).*/\1/p' "$1/source.properties" 2>/dev/null; }

ensure_ndk() {
  local cand
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  for cand in "${sdk:+${sdk}/ndk/${NDK_REVISION}}" "${ANDROID_NDK_ROOT:-}"; do
    if [[ -n "$cand" && -f "$cand/source.properties" ]] && (( $(ndk_major "$cand") >= 27 )); then
      echo "$cand"; return
    fi
  done
  case "$(host_os)" in
    linux)
      local dir="${CACHE}/android-ndk-${NDK_VERSION}"
      if [[ ! -d "$dir" ]]; then
        log "fetching NDK ${NDK_VERSION} (linux)"
        curl -fsSL -o "${CACHE}/ndk.zip" "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
        (cd "$CACHE" && unzip -q ndk.zip && rm ndk.zip)
      fi
      echo "$dir" ;;
    darwin)
      # The dmg is mounted read-only; no 2.5 GB unpack.
      local dmg="${CACHE}/android-ndk-${NDK_VERSION}-darwin.dmg" mnt="${CACHE}/ndk-${NDK_VERSION}-mnt"
      if [[ ! -s "$dmg" ]]; then
        log "fetching NDK ${NDK_VERSION} (darwin dmg)"
        curl -fsSL -o "${dmg}.part" "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-darwin.dmg"
        mv "${dmg}.part" "$dmg"
      fi
      local app
      app="$(find "$mnt" -maxdepth 1 -name 'AndroidNDK*.app' 2>/dev/null | head -1)"
      if [[ -z "$app" ]]; then
        mkdir -p "$mnt"
        hdiutil attach -readonly -nobrowse -mountpoint "$mnt" "$dmg" >/dev/null
        app="$(find "$mnt" -maxdepth 1 -name 'AndroidNDK*.app' | head -1)"
      fi
      echo "${app}/Contents/NDK" ;;
  esac
}

NDK="$(ensure_ndk)"
[[ -f "$NDK/source.properties" ]] || die "NDK not found at $NDK"
TC="${NDK}/toolchains/llvm/prebuilt/$(host_os)-x86_64"
log "NDK $(ndk_major "$NDK") at $NDK"

export CC="${TC}/bin/clang --target=${TARGET}${ANDROID_API}"
export CXX="${TC}/bin/clang++ --target=${TARGET}${ANDROID_API}"
export AR="${TC}/bin/llvm-ar" RANLIB="${TC}/bin/llvm-ranlib" LD="${TC}/bin/ld.lld" STRIP="${TC}/bin/llvm-strip"
export CFLAGS="-O2 -fPIC"
export LDFLAGS="${PAGE_FLAGS}"
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
