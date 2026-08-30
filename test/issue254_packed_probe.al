E := enum { A(u64), B(u64) }
P := @packed struct { items : [E; 2] }
main := fn() -> u64 {
  p := P(items = [E.A(1), E.B(2)])
  match p.items[1] {
    E::A(v) => { return v }
    E::B(v) => { return v }
  }
}
