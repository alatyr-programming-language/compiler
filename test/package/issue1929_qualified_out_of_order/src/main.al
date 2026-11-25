main := fn() -> u64 {
  v := geo::S(b = 2, a = 40)
  return v.a + 2
}
## Compiled alone (the corpus walk), this file names a module it does not have.
## expect: reject
