## e2e — a Slice(T) FIELD compares CONTENT, not its data-pointer word.
## Equal contents at different addresses must compare equal; the same base with a
## different length must compare unequal. The field path is deliberately direct:
## `p.v == q.v`, not a workaround that extracts the view first.
Pair := struct { v : Slice(u64) }

main := fn() -> u64 {
  xs : [u64; 2] = [40, 2]
  ys : [u64; 2] = [40, 2]
  p := Pair(v = xs[0..2])
  q := Pair(v = ys[0..2])
  short := Pair(v = xs[0..1])
  if p.v != q.v { return 1 }
  if p.v == short.v { return 2 }
  return 42
}
