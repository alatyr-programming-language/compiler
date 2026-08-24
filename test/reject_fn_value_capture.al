## FN-10 — a CAPTURING lambda coerced to a bare fn-value type MUST be rejected fail-loud, NOT silently
## miscompiled. A bare `fn(u64) -> u64` is a ONE-WORD code pointer (Functions §1.5): it has no room for
## a captured environment. Storing a capturing lambda `fn(x) { x + k }` (which closes over the outer
## local `k`) in a `fn(u64) -> u64` struct field would drop the environment — the type-erased `dyn`
## (§1.6, FN-11) is the construct for a heterogeneous capturing closure, and it is a separate task. The
## lean lower rejects the un-lifted lambda in this position (build fails, non-zero rc), so no silent
## capture loss occurs. (A NON-capturing lambda / a named top-level fn IS a valid fn value — see
## fn_value_type.al / lambda_value.al.)
Ops := struct { op : fn(u64) -> u64 }
main := fn() -> u64 {
  k := 40
  o := Ops(op = fn(x : u64) -> u64 { return x + k })
  return o.op(2)
}
