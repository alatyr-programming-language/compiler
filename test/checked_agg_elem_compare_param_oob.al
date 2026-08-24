## Checked bounds for the supported by-reference fixed-array aggregate-element comparison slice.
## The element address is valid only for i < N; the compiler must trap before reading caller storage.
P := struct { x : u64, y : u64 }
cmp := fn(ps : [P; 2]) -> u64 {
  if ps[2] == ps[0] { return 1 }
  return 42
}
main := fn() -> u64 {
  ps : [P; 2] = [P(x = 1, y = 2), P(x = 3, y = 4)]
  cmp(ps)
}
