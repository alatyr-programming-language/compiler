## #1180 — `for x in xs[lo..hi]` over a range of a `Slice(u64)` PARAMETER walks the param's elements
## lo..hi in order (Control Flow §5.4, `for`). Expected exit 21. The parent exited 30.
f := fn(xs : Slice(u64)) -> u64 {
  mut n : u64 = 0
  for x in xs[1..xs.len] {
    n = n * 10 + x
  }
  n
}

main := fn() -> u64 {
  t : [u64; 3] = [7, 2, 1]
  f(t[0..3])
}
## expect: run 21
