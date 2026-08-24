## FN-6 — a call applied to a CALL RESULT (`mk()(41)`) must be rejected fail-loud, NOT silently
## miscompiled. A call carries a callee NAME SPAN, not an expression, so the trailing `(41)` used to
## be silently DROPPED and `mk()`'s fn value — `add1`'s CODE ADDRESS — leaked out as the result (17,
## not 42). An ELEMENT callee now works (`fn_value_expr_callee`) because the representation borrows the
## callee NAME SPAN from the chain's root VARIABLE, which resolves to a bound local and so satisfies
## `check`. A call result has no such root: the only name to borrow would be the INNER call's callee
## (`mk`), whose DECLARED arity `check` would then compare against THIS call's argument count and
## wrong-reject the program. Lifting that is a `check` change, not a lowering one — so this shape stays
## rejected. Bind the result to a name first: `k := mk()` then `k(41)` (locked by
## `fn_value_bound_callee`).
add1 := fn(x : u64) -> u64 { return x + 1 }
mk := fn() -> fn(u64) -> u64 { return add1 }
main := fn() -> u64 {
  return mk()(41)
}
