## `get` is `m::get`, declared `-> ptr(mut S)` in `m`, so `deref(get(p))` is an `m::S` (Modules §3,
## §4.1), three words with `a` last. The root's own `S` is one word. Due 42.
get := m::get
S := struct { a : u64 }
viadecl := fn(p : ptr(mut m::S)) -> u64 {
  v := deref(get(p))
  v.a * 2
}
main := fn() -> u64 {
  mut t := m::mk()
  mine := S(a = 0)
  viadecl(ptr(mut t)) + mine.a
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
