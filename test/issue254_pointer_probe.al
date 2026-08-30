E := enum { A(u64), B(u64) }
S := struct { items : [E; 2] }
main := fn() -> u64 {
  s := S(items = [E.A(1), E.B(2)])
  p := ptr(s)
  match deref(p).items[1] {
    E::A(v) => { return v }
    E::B(v) => { return v }
  }
}
