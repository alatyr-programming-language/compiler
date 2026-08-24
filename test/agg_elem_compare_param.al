## P1 aggregate-array equality — a by-reference fixed-array parameter whose elements are
## plain structs with only word-sized scalar fields. Both indices are runtime values and
## the roots differ, so the lower must compare every element word through the ABI pointer.
P := struct { x : u64, y : u64, z : u64 }
cmp := fn(ps : [P; 3], qs : [P; 3]) -> u64 {
  mut i := 0
  mut j := 1
  if ps[i] == qs[j] { return 1 }
  if ps[2] != qs[2] { return 2 }
  return 42
}
main := fn() -> u64 {
  ps : [P; 3] = [P(x = 1, y = 2, z = 3), P(x = 4, y = 5, z = 6), P(x = 7, y = 8, z = 9)]
  qs : [P; 3] = [P(x = 0, y = 0, z = 0), P(x = 1, y = 5, z = 3), P(x = 7, y = 8, z = 9)]
  cmp(ps, qs)
}
