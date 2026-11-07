## e2e (#1233) — `MIN % -1` in a `comptime for` range bound: a diagnostic under `unchecked`, the value
## `0` without it. The pair with `comptime_min_mod_neg1_folds_zero.al` is the point of this fixture.
##
## The two modes split, and the spec says so in two places:
##   CHECKED  — Concurrency §6.1: `MIN % -1` is NOT in the checked-overflow set; "its mathematical
##              result `0` is representable, so a checked `%` yields `0` and does not trap". At comptime
##              that is a value, so the bound folds to `0` and the loop runs zero times.
##   UNCHECKED — Concurrency §6.2 puts `MIN % -1` among the operations that "do whatever the target
##              does", and Comptime §2.6 then refuses to reproduce a hardware behaviour the evaluator
##              does not have: it "remains a **diagnostic** at comptime".
## So the SAME expression is refused here and folds to `0` in its twin. A compiler that guarded both
## modes alike, or neither, fails one of the two fixtures.
##
## Measured on the parent (native x86_64, `seed/alatyr`): SIGFPE, rc 136, no message, no location.
main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. unchecked ((0 - 9223372036854775807 - 1) % (0 - 1)) { total = total + 1 }
  if total != 0 { return 1 }
  return 42
}
## expect: reject "divides the minimum value of its type by -1" "at line 17 in "
