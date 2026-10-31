## Regression: the checked overflow guard follows the OPERAND TYPE, never the shape of a subexpression.
##
## This file used to assert the opposite. It expected `25`, on the reasoning that `-a` desugars to
## `Unchecked(0 - a)`, whose runtime word is the large unsigned pattern `2^64-5`, so an unsigned carry
## guard on the enclosing `+` would see a "spurious" CARRY and trap a sum that "fits" as the signed
## `30 + (-5) = 25`. Owner decision A and spec §6.5 falsify that reading: signedness is a property of the
## VALUE. At type `u64` the value `-a` IS `2^64-5`, the sum IS `2^64+25`, that does not fit in 64 bits,
## and the carry is therefore not spurious — the program has overflowed an unsigned integer and MUST trap.
## A subexpression's spelling is not its type, so the shape of `-x` votes nothing about the guard.
##
## The same program at `i64` answers 25 and must keep doing so: see
## `test/accept_neg_operand_signed_guard.al`, which is the other half of the rule.
##
## Expected: TRAP (SIGILL, exit 132) on x86_64 — `jnc` after the `addq`, with a located diagnostic.
main := fn() -> u64 {
  a := u64(5)
  u64(30 + -a)
}
## expect: trap
