#!/usr/bin/env bash
# Static-FFI spike: an executable linked against static libecl.a, sqlite3 and
# libuv that calls sqlite3_libversion / uv_version_string through CFFI
# (c-inline, no dlopen). Output: work/static-ffi-<target>/static-ffi, run and
# checked at the end.
#
# Usage: scripts/build-static-ffi.sh [host|android-arm64]
#   host           SQLITE_A / LIBUV_A static archives (default: Homebrew on darwin,
#                  multiarch lib dir on Linux); UV_CFLAGS locates uv.h for the grovel run
#   android-arm64  sqlite3 ($SQLITE_AMALGAMATION) and libuv ($LIBUV_VERSION) are built
#                  with the NDK; the result is a static bionic executable run like hello
#   CFFI_DIR       patched CFFI tree (default: egao1980/cffi at $CFFI_COMMIT, fetched)
source "$(dirname "$0")/common.sh"

CFFI_COMMIT=6583fde4c742f9ed3e7191c291befa9722d8fb1f # egao1980/cffi cursor/ecl-static-ffi-1989
ALEXANDRIA_COMMIT=f283e25efbe9f4323419a138b22ad2fc027f6641
BABEL_COMMIT=4eaf3f228be4f6860ccc0b0fbb4c1781a1ee6597
TRIVIAL_FEATURES_COMMIT=828246a1c1efdcad94c1ba2f2a210bb9cb4cde3e
SQLITE_AMALGAMATION=2025/sqlite-amalgamation-3500400
LIBUV_VERSION=1.51.0

target="${1:-host}"

fetch_git() { # URL COMMIT DEST
  local url="$1" commit="$2" dest="$3"
  [[ -f "${dest}/.fetched-${commit}" ]] && return
  rm -rf "$dest" && mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" fetch -q --depth 1 "$url" "$commit"
  git -C "$dest" checkout -q FETCH_HEAD
  touch "${dest}/.fetched-${commit}"
}

LISP="${CACHE}/lisp"
if [[ -z "${CFFI_DIR:-}" ]]; then
  CFFI_DIR="${LISP}/cffi"
  fetch_git https://github.com/egao1980/cffi "$CFFI_COMMIT" "$CFFI_DIR"
fi
fetch_git https://gitlab.common-lisp.net/alexandria/alexandria.git "$ALEXANDRIA_COMMIT" "${LISP}/alexandria"
fetch_git https://github.com/cl-babel/babel "$BABEL_COMMIT" "${LISP}/babel"
fetch_git https://github.com/trivial-features/trivial-features "$TRIVIAL_FEATURES_COMMIT" "${LISP}/trivial-features"

build_android_natives() {
  local dir="${CACHE}/natives-android-arm64-api${ANDROID_API}" src
  SQLITE_A="${dir}/lib/libsqlite3.a" LIBUV_A="${dir}/lib/libuv.a"
  UV_CFLAGS="-I${dir}/include"
  [[ -f "$SQLITE_A" && -f "$LIBUV_A" ]] && return
  mkdir -p "${dir}/lib" "${dir}/include" "${dir}/src"
  src="${dir}/src/$(basename "$SQLITE_AMALGAMATION")"
  if [[ ! -d "$src" ]]; then
    log "fetching ${SQLITE_AMALGAMATION}"
    curl -fsSL -o "${src}.zip" "https://www.sqlite.org/${SQLITE_AMALGAMATION}.zip"
    (cd "${dir}/src" && unzip -q "${src}.zip" && rm "${src}.zip")
  fi
  log "sqlite3 (NDK)"
  $CC -O2 -fPIC -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_THREADSAFE=1 -c "${src}/sqlite3.c" -o "${dir}/src/sqlite3.o"
  "$AR" rcs "$SQLITE_A" "${dir}/src/sqlite3.o"
  src="${dir}/src/libuv-${LIBUV_VERSION}"
  if [[ ! -d "$src" ]]; then
    log "fetching libuv ${LIBUV_VERSION}"
    curl -fsSL "https://github.com/libuv/libuv/archive/refs/tags/v${LIBUV_VERSION}.tar.gz" | tar -xz -C "${dir}/src"
  fi
  log "libuv (NDK, cmake)"
  env -u CC -u CXX -u CFLAGS -u LDFLAGS cmake -S "$src" -B "${src}/build" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="${NDK}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-${ANDROID_API}" \
    -DCMAKE_BUILD_TYPE=Release -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DBUILD_TESTING=OFF \
    >"${dir}/libuv-cmake.log" 2>&1 || { tail -30 "${dir}/libuv-cmake.log"; die "libuv cmake failed"; }
  make -C "${src}/build" -j"$(ncpu)" >"${dir}/libuv-make.log" 2>&1 \
    || { tail -30 "${dir}/libuv-make.log"; die "libuv make failed"; }
  cp "$(find "${src}/build" -maxdepth 1 -name 'libuv*.a' | head -1)" "$LIBUV_A"
  cp -R "${src}/include/." "${dir}/include/"
}

EXTRA_LIBS=""
case "$target" in
  host)
    "$(dirname "$0")/build-ecl-host.sh"
    "$(dirname "$0")/build-ecl-host.sh" --static
    TARGET_INFO="${OUT}/host-static/target-info.lisp"
    case "$(host_os)" in
      darwin)
        SQLITE_A="${SQLITE_A:-$(brew --prefix sqlite)/lib/libsqlite3.a}"
        LIBUV_A="${LIBUV_A:-$(brew --prefix libuv)/lib/libuv.a}"
        UV_CFLAGS="${UV_CFLAGS:--I$(brew --prefix libuv)/include}" ;;
      linux)
        multiarch="$(cc -print-multiarch 2>/dev/null || true)"
        SQLITE_A="${SQLITE_A:-/usr/lib/${multiarch}/libsqlite3.a}"
        LIBUV_A="${LIBUV_A:-/usr/lib/${multiarch}/libuv.a}"
        UV_CFLAGS="${UV_CFLAGS:-}"
        EXTRA_LIBS="-lpthread -ldl -lm" ;;
    esac ;;
  android-arm64)
    "$(dirname "$0")/build-ecl-host.sh"
    # --hello also leaves the 64-aligned TLS anchor object bionic needs.
    "$(dirname "$0")/build-ecl-android.sh" --hello
    source "$(dirname "$0")/android-env.sh"
    build_android_natives
    TARGET_INFO="${OUT}/android-arm64/target-info.lisp"
    EXTRA_LIBS="-static ${WORK}/android-arm64/tls-align.o -lm ${PAGE_FLAGS}" ;;
  *) die "unknown target $target" ;;
esac
for a in "$SQLITE_A" "$LIBUV_A"; do [[ -f "$a" ]] || die "missing static archive $a"; done

OUTDIR="${WORK}/static-ffi-${target}"
rm -rf "$OUTDIR" && mkdir -p "$OUTDIR"
log "link static-ffi for ${target} (sqlite3 + libuv, :cffi-static-link)"
CSM_TARGET_INFO="$TARGET_INFO" \
CSM_LISP_DIRS="${CFFI_DIR}:${LISP}/alexandria:${LISP}/babel:${LISP}/trivial-features" \
CSM_NATIVE_LIBS="${SQLITE_A} ${LIBUV_A} ${EXTRA_LIBS}" \
CSM_GROVEL_FLAGS="${UV_CFLAGS}" \
CSM_OUTPUT="${OUTDIR}/static-ffi" CSM_WORK="${OUTDIR}/" \
  "${OUT}/host/bin/ecl" --norc --load "${ROOT}/static-ffi/build.lisp"

log "run ${OUTDIR}/static-ffi"
case "$target" in
  android-arm64)
    file -b "${OUTDIR}/static-ffi" | tee "${OUTDIR}/ldd.txt"
    grep -q "statically linked" "${OUTDIR}/ldd.txt" || die "not a static executable"
    run_android "${OUTDIR}/static-ffi" | tee "${OUTDIR}/run.txt" ;;
  host)
    "${OUTDIR}/static-ffi" | tee "${OUTDIR}/run.txt"
    case "$(host_os)" in
      linux)  ldd "${OUTDIR}/static-ffi" | tee "${OUTDIR}/ldd.txt" ;;
      darwin) otool -L "${OUTDIR}/static-ffi" | tee "${OUTDIR}/ldd.txt" ;;
    esac
    ! grep -Eq 'libsqlite3|libuv' "${OUTDIR}/ldd.txt" || die "sqlite3/libuv linked dynamically" ;;
esac
grep -q "libsqlite3 static, libuv static" "${OUTDIR}/run.txt" || die "libraries not marked :static"
log "static-ffi ${target} ok"
