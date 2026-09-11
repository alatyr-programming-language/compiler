## Every name here binds through the ANCESTOR chain (Modules §3): `helper`, `mk` and the type `Pair`
## are non-`pub` declarations of `geo`, and this module is `geo::child`. 20 + 8 + 14 = 42.
pub run := fn() -> u64 {
  p := mk()
  return helper() + p.lo + p.hi
}
