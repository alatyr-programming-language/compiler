## #1154 — a WRITTEN unsigned `0 - x` is a binary subtraction, so it borrows and traps when `x > 0`.
##
## Concurrency §6.5 (spec v1.6.0): "the guard an operation carries is chosen by the operand types and by
## nothing else: an unsigned operation tests the carry out of the result". The unary `-x` the parser
## builds as `0 - x` is a different operation, the negation modulo 2^N with no overflow member (§6.3),
## and it still does not trap (`accept_neg_unsigned_and_unchecked`, `accept_neg_unsigned_hof_clone`).
## The parser records the negation's zero (`ast::neg_zero_is`); a written `0` is never in that record.
##
## `x` comes from a `mut` binding so the operand is not a literal.
## Expected: TRAP on all four backends (132 / 133 / 133 / 134).
## Measured on the parent (#1268 `72c89d45`, native x86_64, its Stage1): exit 9 on all four
## backends, no trap: `y` wrapped to 2^64 - 1, because a zero-left unsigned `-` skipped its guard.
main := fn() -> i64 {
  mut x : u64 = 1
  y : u64 = 0 - x
  if y == 0 { return 7 }
  return 9
}
