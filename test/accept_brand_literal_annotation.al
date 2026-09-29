## Issue #563 / Types §9.1, §9.2 — a literal meeting a BRAND annotation takes its type from it, like the
## constructor form `A(41)` already did: `a : A = 41` for `A := brand(u64)` (refused on the parent), the
## top of a byte brand's range (`n : N = 255`, `N := brand(u8)`), and an exactly representable integer
## in a float brand (`x : F = 2`, `F := brand(f64)`). 41 + 255 - 256 + 2 = 42.
A := brand(u64)
N := brand(u8)
F := brand(f64)
main := fn() -> u64 {
  a : A = 41
  n : N = 255
  x : F = 2
  return u64(a) + u64(n) - 256 + u64(f64(x))
}
