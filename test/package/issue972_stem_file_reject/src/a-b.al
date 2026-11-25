## Issue #972 — a module file whose stem `a-b` is not an identifier. Compiled ALONE it is the root of a
## manifest-less invocation, excluded from the scan, so it is valid and runs; inside the package it is
## scanned and refused (see `../package.al`). Alone it still mangles its symbols by the stem on x86_64
## and aarch64, which `as` refuses: #972's open residual, a known deviation until it is fixed.
seven := fn() -> u64 {
  return 7
}

main := fn() -> u64 {
  return seven()
}
## expect: run 7
