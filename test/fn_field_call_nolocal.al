## e2e (FN-10 — a call THROUGH a fn-VALUE STRUCT FIELD with NO same-named local in scope). `o.f(41)`
## is desugared by the parser into the UFCS shape `Call(f, [o, 41])`, so its callee names neither a
## declared fn nor a local: the front end's undefined-callee diagnostic rejected the whole family with
## `alatyr: check: unbound name` even though the LOWER routes it correctly through the field word
## (`fn_field_call_slot`, one `call *%rax`).
##
## `fn_value_type` only APPEARED to cover this: that program happens to hold a LOCAL named `op` with the
## same fn type as the field it calls, and the `local_in` exemption resolved THAT — so the field call
## rode in on a coincidence. Every receiver/field name here (`o`/`f`, `t`/`g`, `w`/`h`, `q`/`k`) is bound
## NOWHERE as a local or as a top-level fn, so the field path is the only thing that can resolve them.
##
## Covers the return/argument classes the exemption admits — the ones whose result is a ONE-WORD SCALAR:
##   1. ONE user arg      — `o.f(11)`  (the arity `fn_value_type` never exercised)
##   2. TWO user args     — `t.g(10, 5)`
##   3. FLOAT signature   — `w.h(20.0)` (the field's `-> f64` is read off the field's own type text)
##   4. AGGREGATE arg     — `q.k(p)` passes a struct BY-REF through the indirect call
## An AGGREGATE-RETURNING field call bound to a local stays fail-loud — see `reject_fn_field_agg_ret`.
## The struct-field indirect call is x86_64-only GAS (like `fn_value_type`) → run_x86.
## 12 + 15 + 10 + 5 = 42.
add1 := fn(x : u64) -> u64 { return x + 1 }
addk := fn(a : u64, b : u64) -> u64 { return a + b }
half := fn(x : f64) -> f64 { return x * 0.5 }

P := struct { x : u64, y : u64 }
sump := fn(p : P) -> u64 { return p.x + p.y }

Ops1 := struct { f : fn(u64) -> u64, base : u64 }
Ops2 := struct { g : fn(u64, u64) -> u64, base : u64 }
OpsF := struct { h : fn(f64) -> f64, base : u64 }
OpsP := struct { k : fn(P) -> u64, base : u64 }

main := fn() -> u64 {
  ## 1. ONE user arg through the field — add1(11) = 12.
  o := Ops1(f = add1, base = 100)
  r1 := o.f(11)
  ## 2. TWO user args through the field — addk(10, 5) = 15.
  t := Ops2(g = addk, base = 100)
  r2 := t.g(10, 5)
  ## 3. a FLOAT signature through the field — half(20.0) = 10.0.
  w := OpsF(h = half, base = 100)
  r3 := u64(w.h(20.0))
  ## 4. an AGGREGATE argument through the field — sump(P(2, 3)) = 5.
  q := OpsP(k = sump, base = 100)
  p := P(x = 2, y = 3)
  r4 := q.k(p)
  ## 12 + 15 + 10 + 5 = 42.
  r1 + r2 + r3 + r4
}
