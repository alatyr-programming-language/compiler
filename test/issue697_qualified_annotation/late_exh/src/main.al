## Issue #697 — the over-rejection control for `late_nonexh`: the same qualified annotation over a
## complete `match` is accepted.
f := fn(p : ptr(mut zkinds::Kind)) -> u64 {
  q : ptr(zkinds::Kind) = p
  match deref(q) { R => { return 40 }; G => { return 1 }; B => { return 3 } }
  return 2
}
main := fn() -> u64 {
  mut k := zkinds::Kind.R
  return f(ptr(mut k)) + 2
}
