## The control for `ir1723_alias_deref_enum` and `ir1723_alias_deref_struct`: the same aliased callees,
## but the root declares no `E` or `S`, so each pointee name denotes `m`'s type from both modules and
## the read stays built on the shared IR. Due 42.
gete := m::gete
gets := m::gets
rd := fn(q : ptr(m::E)) -> u64 {
  match deref(gete(q)) { A => { return 1 }; B(x) => { return x }; C(x, y) => { return x + y } }
}
viadecl := fn(p : ptr(mut m::S)) -> u64 {
  v := deref(gets(p))
  v.a * 2
}
main := fn() -> u64 {
  e := m::mke()
  mut t := m::mks()
  rd(ptr(e)) + viadecl(ptr(mut t)) - 42
}
