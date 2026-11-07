## e2e (#1233) — a CHECKED `MIN % -1` in a `comptime for` range bound folds to `0`; it is NOT refused.
## The twin of `reject_comptime_for_unchecked_min_mod_neg1.al`, and the two together pin the split.
##
## Concurrency §6.1 (spec v1.6.0): "**`MIN % -1` yields `0`.** The remainder of the minimum value by
## `-1` is **not** in the checked-overflow set: its mathematical result `0` is representable, so a
## checked `%` yields `0` and does **not** trap." Comptime §2.6 releases it for the same reason — its
## behaviour is *defined*, not hardware-defined, so the evaluator HAS a value to produce. Only the
## `unchecked` form of the identical expression is a diagnostic (§2.6's hardware-defined list).
##
## NON-VACUOUS: each bound is `k + (MIN % -1)`, so the loop count IS the evidence — a fold that
## returned anything but `0` (or crashed the host's `idiv`, as the parent did with SIGFPE rc 136)
## changes `total`. Each loop contributes its own digit:
##   1   bound `1 + (MIN % -1)` = 1 iteration, +1
##   9   bound `3 + (MIN % -1)` = 3 iterations, +3 each
## The sum 10 is the pass value.
main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. (1 + ((0 - 9223372036854775807 - 1) % (0 - 1))) { total = total + 1 }
  comptime for i in 0 .. (3 + ((0 - 9223372036854775807 - 1) % (0 - 1))) { total = total + 3 }
  if total != 10 { return 1 }
  return 42
}
## expect: run 42
