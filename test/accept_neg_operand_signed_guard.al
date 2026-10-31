## The other half of spec §6.5: the guard follows the operand TYPE, so the SIGNED case keeps answering.
##
## `test/lower_bugA_neg_operand.al` pins that `u64(30 + -a)` traps, because at `u64` the value `-a` is
## `2^64-5` and the sum overflows. This file pins that the fix did NOT simply turn every such guard off:
## at `i64` the same shape is a signed sum, `-5` is `-5`, `30 + (-5) = 25` fits, and the program must run
## and answer `25`. Together the two files say the guard is chosen by the type and by nothing else — not
## by the presence of a negation in the source, which is what the removed shape predicate keyed on.
##
## Expected: exit 25, no trap.
main := fn() -> i64 {
  a := i64(5)
  i64(30 + -a)
}
## expect: run 25
