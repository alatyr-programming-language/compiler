## Modules §3 — `main` is a SIBLING of `geo`, so calling `geo`'s non-`pub` function is a located
## reject. Before the §3 check covered functions this compiled and ran, silently ignoring privacy.
main := fn() -> u64 {
  return geo::priv_fn()
}
