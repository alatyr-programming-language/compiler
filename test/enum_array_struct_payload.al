## Regression: array of enums with struct payloads — match es[0] then read the struct payload fields.
P := struct { x : u64, y : u64 }
E := enum { A(P), B }
main := fn() -> u64 {
  es := [E.A(P(x = 40, y = 2)), E.B]
  match es[0] { E::A(p) => { return p.x + p.y }; E::B => { return 0 } }
}
