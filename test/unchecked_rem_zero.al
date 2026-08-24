## I11 / CG-7 + CG-13 scoping: the REMAINDER dual of `unchecked_udiv_zero` — inside `unchecked` the
## guard is absent and the hardware decides. Both non-x86 backends define `42 % 0` as the DIVIDEND:
## riscv64 `remu` yields it directly, aarch64 computes `a - (a/b)*b` = `42 - 0*0` = 42. x86_64 has no
## defined value at all — the plain `divq` faults (`#DE` → SIGFPE) and the program never returns.
##   x86_64 → exit 136 (hardware fault)   ·   aarch64 / riscv64 → exit 41 (remainder == 42)
## Classified in-program because the raw remainder (42) would be indistinguishable from an ordinary
## success exit. The checked dual is `checked_rem_zero` (exit 132 on every backend).
rem := fn(a : u64, b : u64) -> u64 { return unchecked (a % b) }
main := fn() -> u64 {
  r := rem(42, 0)
  if r == 42 { return 41 }
  if r == 0 { return 42 }
  return 7
}
