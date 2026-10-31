## Issue #1049 (and #633): unary `-` on the minimum `i64` traps (regression; fixed by #1227).
##
## Concurrency §6.1 makes arithmetic checked by default: an operation whose exact result does not fit
## its type traps, unless the programmer wrote `unchecked` around it (§6.2). `-x` with
## `x = -9223372036854775808` has the exact result 2^63, which no `i64` holds, and this source writes no
## `unchecked`. Before #1227 the builder lowered `-x` as `unchecked { 0 - x }`, so the negation wrapped
## back to `x` and the program returned 7 on all four backends (measured at 2cf60b45).
##
## Measured at seed 0.2.18 on native x86_64: run/132 (x86_64), 133 (aarch64, riscv64), 134 (wasm), the
## trap on each. test/trap_neg_min_signed.al pins the same negation with a `mut` operand reached at run
## time; this one keeps the operand an immutable binding of a constant expression, so a later fold of
## `-x` must still trap rather than produce a value or a compile-time refusal.
main := fn() -> u64 {
  x : i64 = -9223372036854775807 - 1
  y : i64 = -x
  if y < 0 { return 7 }
  return 42
}
## expect: trap
