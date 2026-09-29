## Issue #697 — the over-rejection control for `early_nonexh`.
f := fn(p : ptr(mut akinds::Kind)) -> u64 {
  q : ptr(akinds::Kind) = p
  match deref(q) { R => { return 40 }; G => { return 1 }; B => { return 3 } }
  return 2
}
main := fn() -> u64 {
  mut k := akinds::Kind.R
  return f(ptr(mut k)) + 2
}
