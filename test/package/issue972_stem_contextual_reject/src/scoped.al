## Issue #972 — a module file whose stem is the contextual keyword `scoped`. Compiled alone it is a
## manifest-less root and runs; inside the package it is refused.
main := fn() -> u64 {
  return 6
}
## expect: run 6
