#!/usr/bin/env bash
# Static-FFI spike for the host: a fully static-libecl executable that calls
# sqlite3_libversion and uv_version_string through CFFI (c-inline, no dlopen).
# Output: work/static-ffi-host/static-ffi, run and checked at the end.
#
# Usage: scripts/build-static-ffi.sh
#   SQLITE_A / LIBUV_A  static archives (default: Homebrew on darwin, multiarch lib dir on Linux)
#   UV_CFLAGS           C flags locating uv.h for the grovel run
#   CFFI_DIR            patched CFFI tree (default: egao1980/cffi at $CFFI_COMMIT, fetched)
source "$(dirname "$0")/common.sh"

CFFI_COMMIT=6583fde4c742f9ed3e7191c291befa9722d8fb1f # egao1980/cffi cursor/ecl-static-ffi-1989
ALEXANDRIA_COMMIT=f283e25efbe9f4323419a138b22ad2fc027f6641
BABEL_COMMIT=4eaf3f228be4f6860ccc0b0fbb4c1781a1ee6597
TRIVIAL_FEATURES_COMMIT=828246a1c1efdcad94c1ba2f2a210bb9cb4cde3e

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

EXTRA_LIBS=""
case "$(host_os)" in
  darwin)
    SQLITE_A="${SQLITE_A:-$(brew --prefix sqlite)/lib/libsqlite3.a}"
    LIBUV_A="${LIBUV_A:-$(brew --prefix libuv)/lib/libuv.a}"
    UV_CFLAGS="${UV_CFLAGS:--I$(brew --prefix libuv)/include}"
    ;;
  linux)
    multiarch="$(cc -print-multiarch 2>/dev/null || true)"
    SQLITE_A="${SQLITE_A:-/usr/lib/${multiarch}/libsqlite3.a}"
    LIBUV_A="${LIBUV_A:-/usr/lib/${multiarch}/libuv.a}"
    UV_CFLAGS="${UV_CFLAGS:-}"
    EXTRA_LIBS="-lpthread -ldl -lm"
    ;;
esac
for a in "$SQLITE_A" "$LIBUV_A"; do [[ -f "$a" ]] || die "missing static archive $a"; done

"$(dirname "$0")/build-ecl-host.sh"
"$(dirname "$0")/build-ecl-host.sh" --static

OUTDIR="${WORK}/static-ffi-host"
rm -rf "$OUTDIR" && mkdir -p "$OUTDIR"
log "link static-ffi (sqlite3 + libuv, :cffi-static-link)"
CSM_TARGET_INFO="${OUT}/host-static/target-info.lisp" \
CSM_LISP_DIRS="${CFFI_DIR}:${LISP}/alexandria:${LISP}/babel:${LISP}/trivial-features" \
CSM_NATIVE_LIBS="${SQLITE_A} ${LIBUV_A} ${EXTRA_LIBS}" \
CSM_GROVEL_FLAGS="${UV_CFLAGS}" \
CSM_OUTPUT="${OUTDIR}/static-ffi" CSM_WORK="${OUTDIR}/" \
  "${OUT}/host/bin/ecl" --norc --load "${ROOT}/static-ffi/build.lisp"

log "run ${OUTDIR}/static-ffi"
"${OUTDIR}/static-ffi" | tee "${OUTDIR}/run.txt"
grep -q "libsqlite3 static, libuv static" "${OUTDIR}/run.txt" || die "libraries not marked :static"
case "$(host_os)" in
  linux)  ldd "${OUTDIR}/static-ffi" | tee "${OUTDIR}/ldd.txt"
          ! grep -Eq 'libsqlite3|libuv' "${OUTDIR}/ldd.txt" || die "sqlite3/libuv linked dynamically" ;;
  darwin) otool -L "${OUTDIR}/static-ffi" | tee "${OUTDIR}/ldd.txt"
          ! grep -Eq 'libsqlite3|libuv' "${OUTDIR}/ldd.txt" || die "sqlite3/libuv linked dynamically" ;;
esac
log "static-ffi ok"
