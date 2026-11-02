## e2e (#1233) — a CHECKED `MIN % -1` in a `comptime for` range bound folds to 0 and RUNS.
##
## Concurrency §6.1 (spec v1.6.0): "`MIN % -1` yields `0`. The remainder of the minimum value by `-1`
## is **not** in the checked-overflow set: its mathematical result `0` is representable, so a checked
## `%` yields `0` and does **not** trap." Comptime §2.6 runs the same checked-guard family as run time
## and names `MIN % -1` a diagnostic only **inside an `unchecked`** scope — that half is the sibling
## fixture `reject_comptime_for_unchecked_min_mod_neg1`. So the bound here is `3 + 0`, the loop
## unrolls three times, and the program returns 3 + 40.
##
## Measured on the parent (`cb659603`, native x86_64): x86_64 REFUSED this at line 14 with the
## `MIN / -1` diagnostic, and aarch64, riscv64 and wasm ran it into a trap (133 / 133 / 134). Both
## were wrong: only `MIN / -1` traps.
K : i64 = 0 - 9223372036854775807 - 1
D : i64 = 0 - 1

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. 3 + K % D { c = c + 1 }
  return c + 40
}
## expect: run 43
