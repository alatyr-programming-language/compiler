## e2e REJECT (FN-10) — the BOUNDARY of the fn-VALUE STRUCT FIELD call. `p := o.g(40)` where the field
## `g : fn(u64) -> P` returns an AGGREGATE is resolved by the lower BEFORE the slot table exists, so the
## field's declared `fn(…) -> R` text is out of reach there: the destination `p` would be sized as a
## one-word scalar and every field read out of it is garbage. The lower's own `fnfield_call_ret_span`
## records the contract — this shape "stays fail-loud in `check`".
##
## So the front end's field-call exemption (see `fn_field_call_nolocal`) is restricted to fields whose fn
## type returns a ONE-WORD SCALAR; the struct / enum / `str` return classes stay REJECTED here. This
## fixture LOCKS that boundary: without it, widening the exemption to every fn-typed field silently turns
## this program into `return 0` — a silent miscompile behind an accepted build.
## (The enum SCRUTINEE form `match o.g(x)` is a different path and works — see `fn_field_enum_ret`.)
P := struct { x : u64, y : u64 }

mkp := fn(v : u64) -> P { return P(x = v, y = 2) }

Ops := struct { g : fn(u64) -> P, k : u64 }

main := fn() -> u64 {
  o := Ops(g = mkp, k = 0)
  p := o.g(40)
  return p.x + p.y
}
