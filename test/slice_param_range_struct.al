## #1180 — a range slice of a struct-element `Slice(P)` PARAMETER, bound and iterated, holds the
## param's elements lo..hi (Control Flow §5.4). Expected exit 246: length 2, then `b` = 4 and 6. The
## parent exited 200.
P := struct { a : u64, b : u64 }

f := fn(xs : Slice(P)) -> u64 {
  ys := xs[1..xs.len]
  mut n : u64 = ys.len
  for p in ys {
    n = n * 10 + p.b
  }
  n
}

main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  f(t[0..3])
}
