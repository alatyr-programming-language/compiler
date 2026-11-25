## Issue #972 — a module file under a directory whose stem `my-lib` is not an identifier. Compiled
## alone it is a manifest-less root and runs; inside the package its directory is refused.
main := fn() -> u64 {
  return 9
}
## expect: run 9
