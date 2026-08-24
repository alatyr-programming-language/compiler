## DA-DEEP aggregate leaf — whole-element READ/BIND and WRITE for `xs[i].arr[j]`.
##
## The outer array index and inner array-field index are both dynamic. `Row.pad` places the nested
## array at a non-zero field offset; `P` is three words, so a one-word copy/store loses observable
## fields. `before` proves the read is a value copy, `after` proves the local aggregate RHS write,
## and `write_param` proves the same address path through an `in out` fixed-array parameter. The
## untouched elements plus Row's pad/tail fields are checked as neighbours.
P := struct { a : u64, b : u64, c : u64 }
Row := struct { pad : u64, arr : [P; 3], tail : u64 }

write_param := fn(in out xs : [Row; 2], i : u64, j : u64) -> u64 {
  xs[i].arr[j] = P(a = 70, b = 80, c = 90)
  q := xs[i].arr[j]
  q.a + q.c - 150
}

main := fn() -> u64 {
  mut xs : [Row; 2] = [
    Row(pad = 11, arr = [P(a = 1, b = 2, c = 3), P(a = 4, b = 5, c = 6), P(a = 7, b = 8, c = 9)], tail = 13),
    Row(pad = 21, arr = [P(a = 10, b = 11, c = 12), P(a = 13, b = 14, c = 15), P(a = 16, b = 17, c = 18)], tail = 23)
  ]
  mut i : u64 = 1
  mut j : u64 = 2
  before := xs[i].arr[j]
  p := P(a = 40, b = 50, c = 60)
  xs[i].arr[j] = p
  after := xs[i].arr[j]
  left := xs[1].arr[0]
  other := xs[0].arr[2]
  ps := write_param(xs, 0, 1)
  param := xs[0].arr[1]
  if before.a != 16 or before.b != 17 or before.c != 18 { return 1 }
  if after.a != 40 or after.b != 50 or after.c != 60 { return 2 }
  if left.a != 10 or left.b != 11 or left.c != 12 { return 3 }
  if other.a != 7 or other.b != 8 or other.c != 9 { return 4 }
  if xs[1].pad != 21 or xs[1].tail != 23 { return 5 }
  if param.a != 70 or param.b != 80 or param.c != 90 { return 6 }
  ps + (after.a - 39) + (after.b - 49) + (after.c - 59)
}
