## Regression: a TUPLE with an enum component (`t : (Col, u64)`) — match t.0 (the enum) + t.1.
Col := enum { R, G(u64) }
main := fn() -> u64 {
  t : (Col, u64) = (Col.G(40), 2)
  return match t.0 { Col::R => { 0 }; Col::G(v) => { v } } + t.1
}
