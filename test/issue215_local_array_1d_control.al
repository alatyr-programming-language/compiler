## Issue #215 control: one-dimensional local fixed-array initialization,
## indexing, and write/read-back remain supported while the nested shape is
## fixed.
main := fn() -> u64 {
  mut xs : [u64; 2] = [21, 22]
  if xs[0] != 21 { return 1 }
  xs[1] = 29
  if xs[0] != 21 or xs[1] != 29 { return 2 }
  42
}
