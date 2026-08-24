## I11 / CG-8 + CG-13: `INT64_MIN / -1` is the DIVISION-OVERFLOW member of the checked-overflow set
## (its quotient +2^63 is not representable in `i64`) and must trap through the family's ONE direct
## inline trap, emitted BEFORE the divide: `ud2` on x86_64 (SIGILL, exit 132) — the SAME exit as
## `checked_add_ovf`/`checked_mul_ovf` — `brk #0` on aarch64, `ebreak` on riscv64. Before the guard
## x86_64 faulted in hardware (`#DE`, exit 136) while aarch64 `sdiv` and riscv64 `div` silently
## returned INT64_MIN — a wrong value, not a failure. Both operands arrive as runtime parameters
## (`0 - 1` is a subtraction, not a literal), so no backend can fold the guard away.
divide := fn(a : i64, b : i64) -> i64 { return a / b }
main := fn() -> i64 {
  hi : i64 = 0 - 9223372036854775807
  mn := hi - 1
  neg := 0 - 1
  return divide(mn, neg)
}
