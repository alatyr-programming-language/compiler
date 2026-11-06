## #1398 — Concurrency §6.1 (spec v1.6.0): a CHECKED `MIN % -1` yields `0` and does NOT trap.
##
## "The remainder of the minimum value by `-1` is **not** in the checked-overflow set: its mathematical
## result `0` is representable, so a checked `%` yields `0` and does **not** trap. The compiler guards the
## divisor `== -1` case — the same compare as the `MIN / -1` guard — and produces `0` without executing
## the divide, so no target faults on it (CG-8/CG-13)." Only `MIN / -1` is in the set, and it still
## traps (`checked_div_min_neg1`, `issue606_divmin_narrow_i8`/`_i16`/`_i32`).
##
## On the parent every case here trapped, because all four backends reused the `MIN / -1` guard for `%`:
## x86_64 `ud2` (132), aarch64 `brk` and riscv64 `ebreak` (133), wasm `unreachable` (134). The guard
## now belongs to `/` alone; on x86_64, where `idivq` faults (`#DE`) on `MIN / -1`, a checked signed `%`
## skips the divide on a `-1` divisor and leaves the remainder `0` (§6.1, CG-13: no target faults).
##
## Each case contributes a distinct digit, so a single wrong arm shows in the exit code:
##   1   `i64` `MIN % -1` through a call with two runtime operands (the defect)
##   2   the same inline in `main`
##   4   `isize` `MIN % -1` through a call (the signed native width again, its own type)
##   8   a NON-minimum negative dividend by `-1`, which was already `0` and must stay `0`
##  16   unsigned: `u64::MAX % 7` keeps its value (the `%` arm is shared with the unsigned path)
##  32   unsigned by `1`: the divisor-`-1` rewrite must not reach an unsigned divide's own answer
## The sum 63 is the pass value; any missing arm subtracts its own digit.
rem64 := fn(a : i64, b : i64) -> i64 { return a % b }
remsz := fn(a : isize, b : isize) -> isize { return a % b }
remu := fn(a : u64, b : u64) -> u64 { return a % b }
main := fn() -> u64 {
  mut acc : u64 = 0
  m : i64 = 0 - 9223372036854775807 - 1
  neg : i64 = 0 - 1
  if rem64(m, neg) == 0 { acc = acc + 1 }
  if m % neg == 0 { acc = acc + 2 }
  ms : isize = 0 - 9223372036854775807 - 1
  ns : isize = 0 - 1
  if remsz(ms, ns) == 0 { acc = acc + 4 }
  if rem64(0 - 7, neg) == 0 { acc = acc + 8 }
  u : u64 = 18446744073709551615
  seven : u64 = 7
  if remu(u, seven) == 1 { acc = acc + 16 }
  one : u64 = 1
  if remu(u, one) == 0 { acc = acc + 32 }
  return acc
}
## expect: run 63
