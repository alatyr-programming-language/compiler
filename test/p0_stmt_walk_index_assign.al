## P0 statement-list walk: an index assignment is a non-declaring statement and must not
## hide the later unsigned local annotation from any backend's type recovery.
main := fn() -> u64 {
  mut xs : [u64; 2] = [0, 0]
  xs[0] = 1
  a : u64 = 18446744073709551610
  if 0 < a { return 42 }
  return 7
}
