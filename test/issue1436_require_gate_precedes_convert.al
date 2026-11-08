## Issue #364 / #1436 — Types §4.6 dispatch step (1) precedes step (2): a `T(v)` whose `T` is a required
## type `R = @require(pred) U` and whose operand is assignable to `U` is the built-in contract gate, never
## a competing in-scope `@convert U -> R`.
##
## Types §4.6 (v1.8.0, l.330-331): "(1) when `T` is a required type `R = @require(pred) U` and `v` is
## assignable to the immediate `U`, the built-in contract gate (§8.1); otherwise (2) the **one** in-scope
## `@convert` …", and l.357: "If `v` is assignable to `U`, the gate takes precedence over a competing
## `@convert U`→`R`".
##
## `bump` is such a competing conversion and answers its operand plus one, so the run says which step the
## site took: 41 through the gate, 42 through `bump`. `R(x + 1)` inside `bump` is itself gated (its
## operand is a `u64`), and `bump` is not a candidate in its own body either (§4.6 Termination).
##
## Once #364's brand rule let a required type reach step (2), the site ran `bump` and answered 42.
is_pos := fn(v : u64) -> bool { return v > 0 }

R := @require(is_pos) u64

bump := @convert fn(x : u64) -> R {
  return R(x + 1)
}

main := fn() -> u64 {
  r := R(41)
  u64(r)
}
## expect: run 41
