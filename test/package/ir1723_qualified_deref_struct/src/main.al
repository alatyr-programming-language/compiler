## The control for `ir1723_alias_deref_struct`: the same read with the callee called qualified. Due 42.
S := struct { a : u64 }
viaqual := fn(p : ptr(mut m::S)) -> u64 {
  v := deref(m::get(p))
  v.a * 2
}
main := fn() -> u64 {
  mut t := m::mk()
  mine := S(a = 0)
  viaqual(ptr(mut t)) + mine.a
}
