# Sourced after common.sh: NDK lookup and the android-arm64 toolchain env
# (CC/CXX/AR/RANLIB/LD/STRIP, CFLAGS, LDFLAGS, PAGE_FLAGS, NDK, TC).
# NDK lookup: $ANDROID_HOME/ndk/$NDK_REVISION, then $ANDROID_NDK_ROOT (r27+),
# else fetch $NDK_VERSION into the cache.

TARGET=aarch64-linux-android
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
