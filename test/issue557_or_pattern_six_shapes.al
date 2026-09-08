## Issue #557 / Control Flow §5.1 + §5.2 — OR-patterns PARTICIPATE in the exhaustiveness decision:
## an arm `A | B` covers both alternatives, so grouping variants must not make a complete `match` look
## incomplete. The third over-rejection control, run over all six scrutinee spellings: two groups
## covering four variants, no `_` default, accepted everywhere. Each shape answers 7, and 6 * 7 = 42.
E := enum { A, B, C, D }
H := struct { t : E }
o_param := fn(v : E) -> u64 { match v { A | B => { return 7 }; C | D => { return 0 } } return 0 }
o_deref := fn(q : ptr(E)) -> u64 { match deref(q) { A | B => { return 7 }; C | D => { return 0 } } return 0 }
o_call_src := fn() -> E { return E.B }
main := fn() -> u64 {
  mut total := 0
  total += o_param(E.A)
  a : E = E.A
  match a { A | B => { total += 7 }; C | D => {} }
  b := E.A
  match b { A | B => { total += 7 }; C | D => {} }
  mut d := E.A
  total += o_deref(ptr(mut d))
  h := H(t = E.B)
  match h.t { A | B => { total += 7 }; C | D => {} }
  match o_call_src() { A | B => { total += 7 }; C | D => {} }
  return total
}
