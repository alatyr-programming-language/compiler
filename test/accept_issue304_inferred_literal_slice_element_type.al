## Issue #304 controls — correct stores survive inferred scalar array literals and slices.
main := fn() -> u64 {
  mut xs := [1, 2]
  mut flags := [false, false]
  sx := xs[0..2]
  sf := flags[0..2]
  sx[0] = 40
  sf[0] = true
  if sf[0] { return sx[0] + 2 }
  0
}
