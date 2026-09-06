## e2e (#428) — a store whose left operand is a CALL RESULT. A call produces a value, not storage:
## Grammar §3.3 roots every `place` at an ident, a path or `deref(…)` and admits no `(` anywhere in
## the derivation, and Memory §1.6 forbids a store onto a value-expression outright.
##
## Same silent path as the integer-literal sibling: `f` followed by `(` matched no statement head, the
## line fell to the trailing-expression fallback, and `p_factor` read the `=` as an opening
## parenthesis and the `7` below as its closer. Measured on the parent (`d18fb3f`, x86_64): built rc 0
## and exited 65 — the right-hand side became the function's result and the declared `7` never ran.
##
## Refused in the parser, upstream of all four backends; the harness asserts the wording and the
## reported line, which are deliberately not quoted here, and that no artifact remains.
f := fn() -> u64 { 4 }

main := fn() -> u64 {
  f() = 65
  7
}
