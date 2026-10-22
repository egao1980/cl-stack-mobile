#!/usr/bin/env bash
# Host ECL at the pin: the cross compiler for every other target (ECL_TO_RUN)
# and the native desktop/CI runtime. Output: out/host/{bin,lib,include}.
#
# Usage: scripts/build-ecl-host.sh
source "$(dirname "$0")/common.sh"

PREFIX="${OUT}/host"
SRC="${WORK}/host/ecl"

[[ -x "${PREFIX}/bin/ecl" ]] && already_built "$PREFIX" && exit 0

fetch_ecl_src "$SRC"
cd "$SRC"

args=(--prefix="$PREFIX")
if [[ "$(host_os)" == darwin ]] && command -v brew >/dev/null 2>&1; then
  # Same as Homebrew's ecl formula: link the GMP bottle instead of the bundled copy.
  gmp="$(brew --prefix gmp 2>/dev/null || true)"
  [[ -d "$gmp" ]] && args+=(--enable-gmp=system --with-gmp-prefix="$gmp")
fi

log "configure host ${args[*]}"
./configure "${args[@]}" >"${WORK}/host/configure.log" 2>&1 \
  || { tail -50 "${WORK}/host/configure.log"; die "configure failed"; }
make -j"$(ncpu)" >"${WORK}/host/make.log" 2>&1 \
  || { tail -80 "${WORK}/host/make.log"; die "make failed"; }
rm -rf "$PREFIX"
make install >"${WORK}/host/install.log" 2>&1
finish_install "$PREFIX" host
"${PREFIX}/bin/ecl" --norc --eval '(progn (format t "~a ~a~%" (lisp-implementation-type) (lisp-implementation-version)) (ext:quit 0))'
