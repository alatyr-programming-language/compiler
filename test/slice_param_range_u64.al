## #1180 — a range slice `xs[lo..hi]` of a `Slice(u64)` PARAMETER is a view of the param's elements
## lo..hi (Control Flow §5.4; Types, `Slice(T)`). Expected exit 21: two elements, 2 and 1 (a wrong
## length exits 1). The parent took the range over the caller's {ptr, len} block instead of its data
## and exited 30.
f := fn(xs : Slice(u64)) -> u64 {
  ys := xs[1..xs.len]
  if ys.len != 2 {
    return 1
  }
  ys[0] * 10 + ys[1]
}

main := fn() -> u64 {
  t : [u64; 3] = [7, 2, 1]
  f(t[0..3])
}
