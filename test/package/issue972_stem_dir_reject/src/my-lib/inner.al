## Issue #972 — a module file under a directory whose stem `my-lib` is not an identifier. Compiled
## alone it is a manifest-less root and runs; inside the package its directory is refused. Alone, aarch64
## still mangles it by its path (`my-lib__inner__…`), which `as` refuses: #972's open residual, a known
## deviation until it is fixed.
main := fn() -> u64 {
  return 9
}
## expect: run 9
