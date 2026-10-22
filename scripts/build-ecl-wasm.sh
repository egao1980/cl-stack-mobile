#!/usr/bin/env bash
# Cross ECL for wasm32-emscripten (WECL core: no threads, no TCP, no native compiler).
# Output: out/wasm32/{lib/libecl.a,include,target-info.lisp,ecl.js,ecl.wasm}.
#
# Usage: scripts/build-ecl-wasm.sh [--hello]
#   emcc on PATH is used as-is; otherwise emsdk $EMSDK_VERSION is installed into the cache.
#   ECL_TO_RUN  host ECL (default out/host/bin/ecl, must match the pin)
#   --hello     also link hello/hello.c → out/wasm32/hello/{hello.js,hello.wasm,hello.html}
source "$(dirname "$0")/common.sh"

PREFIX="${OUT}/wasm32"
SRC="${WORK}/wasm32/ecl"
# From ECL's configure (wasm32-unknown-emscripten): 64 KB default stack is too
# small, and Boehm only finds stack roots with the spill-pointers pass.
LINK_FLAGS="-sSTACK_SIZE=1048576 -sBINARYEN_EXTRA_PASSES=--spill-pointers -sALLOW_MEMORY_GROWTH=1"

ensure_emsdk() {
  if command -v emcc >/dev/null 2>&1; then return; fi
  local dir="${CACHE}/emsdk"
  if [[ ! -x "${dir}/emsdk" ]]; then
    log "fetching emsdk"
    git clone -q --depth 1 https://github.com/emscripten-core/emsdk.git "$dir"
  fi
  if [[ ! -f "${dir}/.installed-${EMSDK_VERSION}" ]]; then
    "${dir}/emsdk" install "$EMSDK_VERSION" >&2
    "${dir}/emsdk" activate "$EMSDK_VERSION" >&2
    touch "${dir}/.installed-${EMSDK_VERSION}"
  fi
  # shellcheck disable=SC1091
  EMSDK_QUIET=1 source "${dir}/emsdk_env.sh"
}

ensure_emsdk
log "emcc $(emcc --version | head -1)"
ECL_TO_RUN="$(host_ecl)"
export ECL_TO_RUN

if ! already_built "$PREFIX"; then
  fetch_ecl_src "$SRC"
  cd "$SRC"
  BUILD="$(sh ./src/config.guess)"
  log "configure wasm32-unknown-emscripten (build ${BUILD})"
  emconfigure ./configure --host=wasm32-unknown-emscripten --build="$BUILD" \
    --with-cross-config="${SRC}/src/util/wasm32-unknown-emscripten.cross_config" \
    --prefix="$PREFIX" --disable-shared --with-tcp=no --with-cmp=no \
    >"${WORK}/wasm32/configure.log" 2>&1 \
    || { tail -50 "${WORK}/wasm32/configure.log"; die "configure failed"; }
  emmake make -j"$(ncpu)" >"${WORK}/wasm32/make.log" 2>&1 \
    || { tail -80 "${WORK}/wasm32/make.log"; die "make failed"; }
  rm -rf "$PREFIX"
  emmake make install >"${WORK}/wasm32/install.log" 2>&1
  cp build/bin/ecl.js build/bin/ecl.wasm "$PREFIX/"
  finish_install "$PREFIX" wasm32-emscripten "$LINK_FLAGS"
fi

if [[ "${1:-}" == --hello ]]; then
  mkdir -p "${PREFIX}/hello"
  # One link emits hello.html + hello.js + hello.wasm; hello.js also runs under node.
  # shellcheck disable=SC2086
  emcc -O0 "${ROOT}/hello/hello.c" -I"${PREFIX}/include" \
    "${PREFIX}/lib/libecl.a" "${PREFIX}/lib/libeclgc.a" "${PREFIX}/lib/libeclgmp.a" \
    $LINK_FLAGS -o "${PREFIX}/hello/hello.html"
  log "hello: $(ls "${PREFIX}/hello" | tr '\n' ' ')"
fi
