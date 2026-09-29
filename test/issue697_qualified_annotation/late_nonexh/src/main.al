## Issue #697 / Control Flow §5.1 — a pointer local annotated with a PATH-QUALIFIED enum type (`q :
## ptr(zkinds::Kind)`), the enum's module sorting AFTER this one. `B` is uncovered and there is no
## `_`: refused. The parent resolved the qualified name to nothing and accepted it.
f := fn(p : ptr(mut zkinds::Kind)) -> u64 {
  q : ptr(zkinds::Kind) = p
  match deref(q) { R => { return 40 }; G => { return 1 } }
  return 2
}
main := fn() -> u64 {
  mut k := zkinds::Kind.R
  return f(ptr(mut k)) + 2
}
