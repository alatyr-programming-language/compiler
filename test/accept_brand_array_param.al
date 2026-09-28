## Issue #698 — the over-rejection control: the same `[A; 2]` parameter fed `A`-branded elements every
## legal way — a literal of `A` locals, a whole `[A; 2]` local, a literal of `A(…)` constructors — and a
## plain `[u64; 2]` parameter fed plain literals. 2 + 4*10 = 42 for each branded call; the four results
## are checked and the plain one returned.
A := brand(u64)
take := fn(xs : [A; 2]) -> u64 { return u64(xs[0]) + u64(xs[1]) * 10 }
sum := fn(xs : [u64; 2]) -> u64 { xs[0] + xs[1] }
main := fn() -> u64 {
  x : A = A(2)
  y : A = A(4)
  if take([x, y]) != 42 { return 1 }
  xs : [A; 2] = [A(2), A(4)]
  if take(xs) != 42 { return 2 }
  if take([A(2), A(4)]) != 42 { return 3 }
  return sum([40, 2])
}
