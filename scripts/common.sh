# shellcheck shell=bash
# Shared helpers for scripts/build-ecl-*.sh. Source, do not execute.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../ecl.pin
source "${ROOT}/ecl.pin"

CACHE="${CL_STACK_MOBILE_CACHE:-${HOME}/.cache/cl-stack-mobile}"
OUT="${CL_STACK_MOBILE_OUT:-${ROOT}/out}"
WORK="${CL_STACK_MOBILE_WORK:-${ROOT}/work}"
mkdir -p "$CACHE" "$OUT" "$WORK"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ncpu() {
  if command -v nproc >/dev/null 2>&1; then nproc; else sysctl -n hw.ncpu; fi
}

host_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo darwin ;;
    *) die "unsupported build host $(uname -s)" ;;
  esac
}

# fetch_ecl_src DEST — fresh tree of the pinned commit (tarball cached by sha).
fetch_ecl_src() {
  local dest="$1" tarball="${CACHE}/ecl-${ECL_COMMIT}.tar.gz"
  if [[ ! -s "$tarball" ]]; then
    log "fetching ECL ${ECL_VERSION} (${ECL_COMMIT:0:12})"
    curl -fsSL -o "${tarball}.part" "${ECL_REPO}/archive/${ECL_COMMIT}.tar.gz"
    mv "${tarball}.part" "$tarball"
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xzf "$tarball" -C "$dest" --strip-components=1
}

# host_ecl — ECL that runs the cross compiler. Must be the pinned version.
host_ecl() {
  local ecl="${ECL_TO_RUN:-${OUT}/host/bin/ecl}"
  [[ -x "$ecl" ]] || die "no host ECL at $ecl (run scripts/build-ecl-host.sh or set ECL_TO_RUN)"
  local v
  v="$("$ecl" --norc --eval '(progn (princ (lisp-implementation-version)) (ext:quit 0))' 2>/dev/null)"
  [[ "$v" == "$ECL_VERSION" ]] || die "host ECL $ecl is $v, pin is $ECL_VERSION"
  echo "$ecl"
}

# already_built PREFIX — true when PREFIX holds this pin (FORCE=1 rebuilds).
already_built() {
  [[ "${FORCE:-0}" != 1 ]] && grep -qx "ecl_commit=${ECL_COMMIT}" "$1/build-info.txt" 2>/dev/null \
    && { log "$1 already built at the pin (FORCE=1 to rebuild)"; return 0; }
  return 1
}

# finish_install PREFIX TARGET [LINK_FLAGS...] — flat target-info.lisp + build manifest.
finish_install() {
  local prefix="$1" target="$2"
  shift 2
  local info
  info="$(find "${prefix}/lib" -name target-info.lsp | head -1)"
  if [[ -n "$info" ]]; then
    cp "$info" "${prefix}/target-info.lisp"
  elif [[ -x "${prefix}/bin/ecl" ]]; then
    # Native builds only write target-info.lsp when cross compiling.
    "${prefix}/bin/ecl" --norc --eval '(require :cmp)' \
      --eval "(c::write-target-info #p\"${prefix}/target-info.lisp\")" --eval '(ext:quit 0)' >/dev/null
  else
    die "no target-info.lsp under ${prefix}/lib"
  fi
  {
    echo "target=${target}"
    echo "ecl_version=${ECL_VERSION}"
    echo "ecl_commit=${ECL_COMMIT}"
    echo "link_flags=$*"
  } > "${prefix}/build-info.txt"
  log "${target}: $(cd "$prefix" && ls lib/*.a 2>/dev/null | tr '\n' ' ')"
}

# Run a static aarch64 Linux/bionic executable: natively, qemu, or docker.
run_android() {
  local bin="$1"
  if [[ "$(uname -s)/$(uname -m)" == Linux/aarch64 ]]; then "$bin"
  elif command -v qemu-aarch64-static >/dev/null 2>&1; then qemu-aarch64-static "$bin"
  elif command -v qemu-aarch64 >/dev/null 2>&1; then qemu-aarch64 "$bin"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm --platform linux/arm64 -v "$(dirname "$bin"):/x:ro" alpine "/x/$(basename "$bin")"
  else die "no way to run an arm64 binary here"
  fi
}
