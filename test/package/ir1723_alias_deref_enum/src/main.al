## `get` is `m::get`, declared `-> ptr(E)` in `m`, so `deref(get(q))` is an `m::E` (Modules §3, §4.1).
## The root's own `E` lists the variants in another order. Due 42, or refused at the `match` line.
get := m::get
E := enum { C(u64, u64), B(u64), A }
rd := fn(q : ptr(m::E)) -> u64 {
  match deref(get(q)) { A => { return 1 }; B(x) => { return x }; C(x, y) => { return x + y } }
}
main := fn() -> u64 {
  e := m::mk()
  mine := E.A
  rd(ptr(e))
}
