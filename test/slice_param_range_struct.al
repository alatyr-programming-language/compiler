## #1180 — a range slice of a struct-element `Slice(P)` PARAMETER, bound and iterated, holds the
## param's elements lo..hi (Control Flow §5.4). Expected exit 46: `b` = 4 and 6 (a wrong length exits
## 1). The parent exited 0.
P := struct { a : u64, b : u64 }

f := fn(xs : Slice(P)) -> u64 {
  ys := xs[1..xs.len]
  if ys.len != 2 {
    return 1
  }
  mut n : u64 = 0
  for p in ys {
    n = n * 10 + p.b
  }
  n
}

main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  f(t[0..3])
}
## expect: run 46
