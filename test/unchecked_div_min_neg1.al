## I11 / CG-7 + CG-13 scoping: inside `unchecked` the `MIN / -1` division-overflow guard is ABSENT
## and the operation takes its hardware-defined behaviour. aarch64 `sdiv` and riscv64 `div` both
## DEFINE `INT64_MIN / -1` as INT64_MIN (no fault, no trap); x86_64 `idivq` raises `#DE` (SIGFPE)
## and the program never returns.
##   x86_64 → exit 136 (hardware fault)   ·   aarch64 / riscv64 → exit 41 (quotient == INT64_MIN)
## The quotient is compared IN-PROGRAM: its low byte is 0, so an exit code alone would be
## indistinguishable from an ordinary success. The checked dual is `checked_div_min_neg1` (exit 132
## on every backend). Not registered for wasm: `i64.div_s` traps on `MIN / -1` unconditionally there.
divide := fn(a : i64, b : i64) -> i64 { return unchecked (a / b) }
main := fn() -> i64 {
  hi : i64 = 0 - 9223372036854775807
  mn := hi - 1
  neg := 0 - 1
  q := divide(mn, neg)
  if q == mn { return 41 }
  return 7
}
