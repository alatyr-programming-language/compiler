## The root reaches `geo` through the module alias `g`; `zz`'s `S` is a decoy.
g := geo

main := fn() -> u64 {
  v := g::S(a = 40, b = 2)
  w := g::S(b = 2, a = 40)
  if w.a != 40 { return 1 }
  return v.a + v.b
}
## Compiled alone (the corpus walk), this file names a module it does not have.
## expect: reject
