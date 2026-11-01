## e2e (x86_64 rendering) — #1049: a negated NAME in a `{}` hole now renders, and renders right.
##
## This is the assertion `test/print_hole_unmatched_reject.al` said to write when the hole expansion
## could resolve a negated name's type. It could not, because the parser wrapped `-x` in
## `Expr::Unchecked` and the chain's shape tests all keyed on the OUTER kind — so the argument matched
## no arm and the file pinned the loud refusal instead (#486, #464).
##
## The desugar no longer carries that wrapper (it was a verification-mode grant the source never wrote,
## and it was silently unchecking every operation nested inside the operand). The `Bin` is visible to
## `expr_is_arith_bin`, `print_one_int` receives the value, and the answer is the signed `-5`.
##
## Expected stdout: `v=[-5]\n`, exit 42. Golden in the sibling `.out`.
main := fn() -> u64 {
  x := 5
  print("v=[{}]\n", -x)
  42
}
## expect: run 42
