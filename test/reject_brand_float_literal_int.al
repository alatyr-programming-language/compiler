## Issue #563 / TYP-13 — a float-spelled literal is never an integer initializer, through a brand too.
## The parent accepted `a : A = 1.5` for `A := brand(u64)` and ran it to 1.
A := brand(u64)
main := fn() -> u64 {
  a : A = 1.5
  return u64(a)
}
