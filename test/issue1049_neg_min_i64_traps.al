## Issue #1049 (and #633): unary `-` on the minimum `i64` must trap, and today it wraps.
##
## Concurrency §6.1 makes arithmetic checked by default: an operation whose exact result does not fit
## its type traps, unless the programmer wrote `unchecked` around it (§6.2). `-x` with
## `x = -9223372036854775808` has the exact result 2^63, which no `i64` holds, and this source writes no
## `unchecked`. The builder lowers `-x` as `unchecked { 0 - x }` (#1049), so the subtraction wraps back
## to `x` itself and the program goes on with a negative "negation".
##
## The `## expect:` line below states what the specification requires. What each backend does instead
## is a row of scripts/known-deviations.tsv naming #1049; the fix deletes those rows.
main := fn() -> u64 {
  x : i64 = -9223372036854775807 - 1
  y : i64 = -x
  if y < 0 { return 7 }
  return 42
}
## expect: trap
