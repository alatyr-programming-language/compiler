## Issue #697 — as `late_nonexh`, with the enum's module sorting BEFORE this one (`akinds`), so
## neither declaration order is what decides.
f := fn(p : ptr(mut akinds::Kind)) -> u64 {
  q : ptr(akinds::Kind) = p
  match deref(q) { R => { return 40 }; G => { return 1 } }
  return 2
}
main := fn() -> u64 {
  mut k := akinds::Kind.R
  return f(ptr(mut k)) + 2
}
