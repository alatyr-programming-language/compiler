## Issue #304 — an inferred numeric array literal must retain its slice element type.
main := fn() -> u64 {
  mut xs := [1, 2]
  s := xs[0..2]
  s[0] = "text"
  0
}
