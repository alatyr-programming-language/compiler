## e2e / issue #546 — `bitcast`'s target type decides a relational operator's signedness.
##
## Types §4.2 makes `bitcast` the reinterpret conversion: same bits, the target type decides the
## interpretation. So `unchecked bitcast(i64, x) < 0` is TRUE for a word with its top bit set, whatever
## shape `x` has, and `unchecked bitcast(u64, v) > 0` is TRUE for a negative `i64`. The relational lowering
## used to recover signedness by scanning the operand's source and never looked at the cast, so the
## signed comparison read unsigned and was constant-false: a refusal guard of the form
## `if bitcast(i64, x) < 0 { <refuse> }` never refused.
##
## Covered: the operand as a call, a sum and a struct field (the residual shapes #627 left), the mirror
## `bitcast(u64, <negative i64>) > 0`, a small word that must stay non-negative, and the guard-silencing
## shape as a function that must take its refusal branch. Each check owns a code from 11 up; 42 means all
## held. The high words are written as literals, since `0 - 6` over `usize` traps (checked arithmetic).
##
## NON-VACUOUS: on the parent of #627 (`dc4c819`) the bare `unchecked bitcast(i64, off) < 0` was
## constant-false on all four backends (the #523 lane's guard did nothing); the call, sum and field
## shapes stayed so after #627 (issue comment of that landing). They answer 42 on x86_64 since `55fa477`
## (#1133 lane L2 re-measure), and on all four backends at `dc9e18e2`.
S := struct { off : usize }

f := fn(x : usize) -> usize { x }

refuse := fn(off : usize) -> u64 {
  if unchecked bitcast(i64, f(off)) < 0 { return 1 }
  0
}

main := fn() -> u64 {
  high : usize = 18446744073709551610
  if not (unchecked bitcast(i64, f(high)) < 0) { return 11 }
  if unchecked bitcast(i64, f(6)) < 0 { return 12 }
  a : usize = 18446744073709551606
  b : usize = 4
  if not (unchecked bitcast(i64, a + b) < 0) { return 13 }
  s := S(off = high)
  if not (unchecked bitcast(i64, s.off) < 0) { return 14 }
  v : i64 = 0 - 5
  if not (unchecked bitcast(u64, v) > 0) { return 15 }
  if refuse(high) != 1 { return 16 }
  if refuse(5) != 0 { return 17 }
  42
}
## expect: run 42
