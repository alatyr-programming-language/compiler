## a `match s.c` over a struct's ENUM FIELD in VALUE (expression) position
## (`x := match s.c { … => { v } }`) — the value-match path (emit_gas' Expr::Match), not the
## statement-match path. It previously fell to the integer scrutinee (garbage discriminant); now it
## materializes the field's enum via try_field_enum_scrut, like the statement match. Two enum fields
## + a struct field exercise the field word offsets.
Col := enum { R, G(u64), B }
P := struct { x : u64, y : u64 }
S := struct { a : Col, b : Col, p : P }
main := fn() -> u64 {
  s := S(a = Col.G(30), b = Col.G(8), p = P(x = 3, y = 1))
  x := match s.a { Col::R => { 0 }; Col::G(v) => { v }; Col::B => { 1 } }
  y := match s.b { Col::R => { 0 }; Col::G(v) => { v }; Col::B => { 1 } }
  return x + y + s.p.x + s.p.y     ## 30 + 8 + 3 + 1 = 42
}
