## e2e (field read DIRECTLY off a struct-valued MATCH-EXPRESSION whose arms are a call + a literal).
## `(match c { Col::R => { f() } Col::G => { P(v=7) } }).v` — no intermediate binding. Rewrites to
## a scalar match `match c { … => { <arm>.v } }`, each arm's field read riding the working
## `<call>.field` / struct-literal-field path. Was a silent 0 (field_slot → pushq $0). c=Col.R → 42.
P := struct { v : u64 }
Col := enum { R, G }
f := fn() -> P { return P(v = 42) }
main := fn() -> u64 {
  c := Col.R
  return (match c { Col::R => { f() } Col::G => { P(v = 7) } }).v
}
