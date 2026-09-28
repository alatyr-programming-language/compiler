## Issue #563 — a string literal into a brand over an integer has no conforming reading (Types §4.2), as
## `x : u64 = "x"` has none. The parent accepted it and ran.
A := brand(u64)
main := fn() -> u64 {
  a : A = "x"
  return 1
}
