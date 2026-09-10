## Issue #304 — an inferred boolean array literal must retain its slice element type.
main := fn() -> u64 {
  mut xs := [false, false]
  s := xs[0..2]
  s[0] = "text"
  0
}
