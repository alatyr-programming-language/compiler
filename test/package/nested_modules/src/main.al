## The root package module calls a nested module by its source-path namespace. The callee is `pub`
## (Modules §3) — `main` and `geometry` are siblings, so nothing else would be nameable from here.
main := fn() -> u64 {
  return geometry::vec::answer()
}
