## #1180 — a range slice of a `Slice(str)` PARAMETER holds the param's two-word `str` elements lo..hi
## (Control Flow §5.4). Expected exit 21: the lengths of "de" and "f". The parent read the wrong
## elements.
f := fn(xs : Slice(str)) -> u64 {
  ys := xs[1..xs.len]
  u64(ys[0].len) * 10 + u64(ys[1].len)
}

main := fn() -> u64 {
  t : [str; 3] = ["abc", "de", "f"]
  f(t[0..3])
}
