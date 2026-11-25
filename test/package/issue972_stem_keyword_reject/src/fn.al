## Issue #972 — a module file whose stem is the keyword `fn`. Compiled alone it is a manifest-less root
## and runs; inside the package it is refused.
main := fn() -> u64 {
  return 5
}
## expect: run 5
