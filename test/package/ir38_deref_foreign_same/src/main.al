## `h.p` is an `m::H` field spelled `ptr(S)` in `m`, so `deref(h.p)` is an `m::S` (Modules §3, §4.1):
## three words, `a` last. The root's own `S` is one word and has no `x`. Due 21 + 20 + 1 = 42.
S := struct { a : u64 }
rd := fn(h : m::H) -> u64 {
  v := deref(h.p)
  v.a + v.x + h.k
}
main := fn() -> u64 {
  mut t := m::mk()
  h := m::H(p = ptr(t), k = 21)
  mine := S(a = 0)
  rd(h) + mine.a
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
