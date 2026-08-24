## Modules §3 — a SIBLING may not read `geo`'s non-`pub` constant, qualified spelling included.
main := fn() -> u64 {
  return geo::PRIV_C
}
