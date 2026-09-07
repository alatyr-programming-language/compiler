## Issue #557 / Control Flow §5.1 — the OVER-REJECTION control for the six scrutinee shapes: a `match`
## that covers EVERY variant and carries no `_` default is exhaustive and must still be ACCEPTED, in
## every one of the six spellings the widened check now decides. The six shapes contribute
## 6 + 3 + 3 + 3 + 3 + 2 = 20; the constant lifts it to the fixture convention's 42.
C := enum { R, G, B }
H := struct { t : C }
p_param := fn(c : C) -> u64 { match c { R => { return 1 }; G => { return 2 }; B => { return 3 } } return 0 }
p_deref := fn(q : ptr(C)) -> u64 { match deref(q) { R => { return 1 }; G => { return 2 }; B => { return 3 } } return 0 }
p_call_src := fn() -> C { return C.G }
main := fn() -> u64 {
  mut total := 0
  total += p_param(C.R) + p_param(C.G) + p_param(C.B)
  a : C = C.B
  match a { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  b := C.B
  match b { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  mut d := C.B
  total += p_deref(ptr(mut d))
  h := H(t = C.B)
  match h.t { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  match p_call_src() { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  return total + 22
}
