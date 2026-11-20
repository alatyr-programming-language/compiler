rd := fn(h : m::H) -> u64 {
  v := deref(h.p)
  v.a + h.k
}
main := fn() -> u64 {
  mut s := a::S(x = 1, a = 2)
  rd(m::mk(ptr(s), 40))
}
## Compiled alone (the corpus walk), this file names modules it does not have.
## expect: reject
