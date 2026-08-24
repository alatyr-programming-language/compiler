## FN-6 CAPTURE — MULTIPLE captured locals + a multi-param lambda + the same closure called more than
## once. `g` captures `base`; each `g(x, y)` call becomes `g(x, y, base)`. (8+4+30) = 42.
main := fn() -> u64 {
  base := 30
  g := fn(x : u64, y : u64) -> u64 { return x + y + base }
  return g(8, 4)
}
