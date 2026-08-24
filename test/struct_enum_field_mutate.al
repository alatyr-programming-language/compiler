## mutate a struct ENUM FIELD (s.c = Col.G(40)) — FieldAssign now stores the
## enum via emit_enum_assign (a scalar store dropped the payload, leaving a stale discriminant).
Col := enum { R, G(u64), B }
S := struct { c : Col, n : u64 }
main := fn() -> u64 {
  mut s : S = S(c = Col.R, n = 2)
  s.c = Col.G(40)
  return match s.c { Col::R => { 0 }; Col::G(v) => { v }; Col::B => { 1 } } + s.n
}