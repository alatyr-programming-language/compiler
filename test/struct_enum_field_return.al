## ROADMAP §4: return a struct with an ENUM FIELD by value — emit_struct_value materializes a
## StructLit with a non-str multi-word field via emit_struct_assign, then delivers its words to the
## return registers (the per-field push only knew str + scalar, dropping the enum payload).
Col := enum { R, G(u64) }
S := struct { c : Col, n : u64 }
mk := fn() -> S { return S(c = Col.G(40), n = 2) }
main := fn() -> u64 {
  s := mk()
  return match s.c { Col::R => { 0 }; Col::G(v) => { v } } + s.n
}