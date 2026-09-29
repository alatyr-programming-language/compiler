## Issue #698 — the same parameter fed a WHOLE array LOCAL of the sibling brand (`bs : [B; 2]`). The
## element walk read only array literals, so a whole array value crossed with every element; the
## parent ran this to 32. Its elements are now judged by the local's recorded element type.
A := brand(u64)
B := brand(u64)
take := fn(xs : [A; 2]) -> u64 { return u64(xs[0]) + u64(xs[1]) * 10 }
main := fn() -> u64 {
  b : B = B(2)
  c : B = B(3)
  bs : [B; 2] = [b, c]
  return take(bs)
}
