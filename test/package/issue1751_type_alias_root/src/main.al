S := n::S

main := fn() -> u64 {
  s := S(b = 2, a = 40)
  return s.a + s.b + m::own()
}
## Compiled alone (the corpus walk), this file names a module it does not have.
## expect: reject
