#!/usr/bin/env bash
# Host ECL at the pin: the cross compiler for every other target (ECL_TO_RUN)
# and the native desktop/CI runtime. Output: out/host/{bin,lib,include}.
#
# Usage: scripts/build-ecl-host.sh [--static]
#   --static  build out/host-static instead: --disable-shared libecl.a, the
#             native link target for static executables (static-FFI spike).
source "$(dirname "$0")/common.sh"

name=host
args=()
if [[ "${1:-}" == --static ]]; then
  name=host-static
  args+=(--disable-shared)
fi
PREFIX="${OUT}/${name}"
SRC="${WORK}/${name}/ecl"

[[ -x "${PREFIX}/bin/ecl" ]] && already_built "$PREFIX" && exit 0

fetch_ecl_src "$SRC"
cd "$SRC"

args+=(--prefix="$PREFIX")
if [[ "$(host_os)" == darwin ]] && command -v brew >/dev/null 2>&1; then
  # Same as Homebrew's ecl formula: link the GMP bottle instead of the bundled copy.
  gmp="$(brew --prefix gmp 2>/dev/null || true)"
  [[ -d "$gmp" ]] && args+=(--enable-gmp=system --with-gmp-prefix="$gmp")
fi

log "configure ${name} ${args[*]}"
./configure "${args[@]}" >"${WORK}/${name}/configure.log" 2>&1 \
  || { tail -50 "${WORK}/${name}/configure.log"; die "configure failed"; }
make -j"$(ncpu)" >"${WORK}/${name}/make.log" 2>&1 \
  || { tail -80 "${WORK}/${name}/make.log"; die "make failed"; }
rm -rf "$PREFIX"
make install >"${WORK}/${name}/install.log" 2>&1
finish_install "$PREFIX" "$name"
"${PREFIX}/bin/ecl" --norc --eval '(progn (format t "~a ~a~%" (lisp-implementation-type) (lisp-implementation-version)) (ext:quit 0))'
