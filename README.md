# cl-stack-mobile

Toolchain for running cl-stack apps on Android, iOS and in the browser
(plan of record: `docs/MOBILE-APP-PLAN.md` in the cl-stack workspace). Lisp is the
in-process app core, compiled ahead of time with **ECL**; this repo pins ECL,
cross-builds it for every target, and carries the static-FFI path.

| Target | Script | Output (`out/<target>/`) | Proof (`scripts/verify-hello.sh <target>`) |
|---|---|---|---|
| host (linux / darwin) | `build-ecl-host.sh` | `bin/ecl` (cross compiler), `lib`, `include`, `target-info.lisp` | C shell links `libecl`, prints `(lisp-implementation-version)` |
| `wasm32` (emscripten) | `build-ecl-wasm.sh --hello` | `lib/libecl.a`, `include`, `target-info.lisp`, `ecl.{js,wasm}`, `hello/hello.{html,js,wasm}` | `node hello.js`; `hello.html` is the page |
| `android-arm64` (API 24, NDK r27c) | `build-ecl-android.sh --hello` | `lib/libecl.a` + `libeclgc.a` `libeclgmp.a` `libeclatomic.a`, `include`, `target-info.lisp` | static bionic `hello-ecl` under qemu / docker arm64; all LOAD segments 16 KB aligned |
| `ios-sim-arm64` (iOS 15) | `build-ecl-ios-sim.sh --hello` | same archives, `include`, `target-info.lisp` | `xcrun simctl spawn` of `hello-ecl` in a booted iPhone simulator |

Each `out/<target>/build-info.txt` records the ECL commit and the link flags the
consumer must reuse (16 KB pages on Android, `-framework Foundation` on iOS,
stack size + `--spill-pointers` on wasm).

## Pin

[`ecl.pin`](ecl.pin): ECL `26.5.5` at `74780fa2`, from
[`egao1980/ecl`](https://github.com/egao1980/ecl) (mirror of
[upstream](https://gitlab.com/embeddable-common-lisp/ecl) `develop` + tags;
our patches land there first). Every cross build needs a host ECL of the
same version (`ECL_TO_RUN`, default `out/host/bin/ecl`), so build the host first:

```bash
scripts/build-ecl-host.sh
scripts/build-ecl-android.sh --hello && scripts/verify-hello.sh android-arm64
scripts/build-ecl-wasm.sh --hello    && scripts/verify-hello.sh wasm32
scripts/build-ecl-ios-sim.sh --hello && scripts/verify-hello.sh ios-sim-arm64   # Xcode
```

Toolchains (NDK, emsdk) are fetched into `~/.cache/cl-stack-mobile`
(`CL_STACK_MOBILE_CACHE`), never installed system-wide. On macOS the NDK dmg is
mounted read-only rather than unpacked. `FORCE=1` rebuilds a target already
built at the pin.

CI: [`cross.yml`](.github/workflows/cross.yml) builds and verifies wasm32 and
android-arm64 on ubuntu and ios-sim-arm64 on `macos-14`, uploading the archives.

## Mobile subset

[`pins/mobile.lisp`](pins/mobile.lisp) lists the systems that must pass the
`test-ecl` lane and are cross-compiled into app images. `(stack-mobile:mobile-subset)`
reads it; `(stack-mobile:device-subset)` drops host-only entries (Ironclad).

## Static FFI

`scripts/build-static-ffi.sh [host|android-arm64]` links one executable from
static `libecl.a`, sqlite3 and libuv, with CFFI's whole closure compiled for the
target (`compile-file :target`, `:system-p t`). With the `:cffi-static-link`
feature, the [`egao1980/cffi`](https://github.com/egao1980/cffi) branch
`cursor/ecl-static-ffi-1989` emits `ffi:c-inline` calls (plain `extern` symbols
resolved by the linker), and `define-foreign-library` / `use-foreign-library`
mark the library `:static` instead of calling `dlopen`. The uv grovel file runs
on the host. Both targets print the library versions; android-arm64 is a static
bionic executable run like `hello-ecl`. The driver is
[`static-ffi/build.lisp`](static-ffi/build.lisp).

## Not yet

Bridge frames (JSON over JNI / `WKScriptMessageHandler`), host shells, and the
`stack-mobile` CLI are later P0/P1 steps.

OCI overlays for `platform.os` `android` / `ios` need these changes in
cl-repository:

- `platform-resolver`: `detect-local-os` knows only linux/darwin/windows/bsd.
  ECL android has `:android :unix` but no `:linux`, so the OS resolves to `nil`,
  and `platform-matches-p` treats `nil` as "any" (a linux overlay would be
  pulled). iOS ECL reports `:darwin`. `detect-local-arch` needs `:aarch64`
  (ECL's feature; `:arm64` only comes from trivial-features).
- Mobile pulls happen on the build host, so the resolver needs an explicit
  target platform (from `target-info.lisp`) instead of `*features*` detection.
- Platform values: `android`/`arm64`, `ios`/`arm64` with the simulator as
  `os.features: ["simulator"]` (or `variant`), and `js`/`wasm` (Go's GOOS/GOARCH
  for emscripten).
- Overlay payload: static archives (`.a`) plus headers and the link flags from
  `build-info.txt`, not `.so`/`.dylib`; plus a prebuilt grovel output per platform.

## License

MIT
