## Issue #563 — representability is still checked THROUGH the brand (§9.1): 300 does not fit the
## `u8` that `N` brands, so the annotated literal is a located error, as `n : u8 = 300` is.
N := brand(u8)
main := fn() -> u64 {
  n : N = 300
  return u64(n)
}
