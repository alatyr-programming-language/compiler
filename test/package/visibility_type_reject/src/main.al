## Modules §3 — a SIBLING may not CONSTRUCT `geo`'s non-`pub` struct type.
main := fn() -> u64 {
  p := geo::Priv(v = 42)
  return p.v
}
