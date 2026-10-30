## #1049 — unary `−` over a SIGNED operand keeps its guard: negating MIN is the checked-overflow
## member Concurrency §6.1 (spec v1.6.0) names by name ("unary `−` (negating the minimum value)"), and
## §6.3 scopes it to `neg` on `iN`.
##
## It did not. The parser desugared `-x` to `Unchecked(Bin(17, Num(0), x))`, and the grant that wrapper
## carries is SCOPED — so it reached past the negation into the operand, and lowering's `ex_is_zero_lit(l)`
## exemption then removed what was left. Measured on x86_64 at origin/main 55fa477: `-MIN` answered
## MIN (reproduction exit 11). Earlier, on 0.2.17 at fdc40f6: `-(a * b)` emitted `imulq` with
## neither `jno` nor `ud2`, where `a * b` written plainly emits both. `-MIN` answered MIN — a silent
## wrong value, the one outcome I11 forbids.
##
## Now: the desugar carries no verification-mode grant, and the guard is chosen by the OPERAND'S TYPE in
## one place (`ir::zero_left_no_overflow`). A signed negation therefore traps through the
## family's ONE direct inline trap (CG-13) — `ud2` on x86_64 (exit 132), `brk #0` on aarch64,
## `ebreak` on riscv64, `unreachable` on wasm.
##
## The operand reaches MIN through a runtime subtraction so the value is not a literal: a literal below a
## type's bound is a COMPILE error (§9.1 / I11), and this fixture is about the run-time operation.
## `m - 1` at i64 does not overflow (0 - 1 = -1), so the only trap in this program is the negation.
main := fn() -> i64 {
  mut m : i64 = -9223372036854775807
  m = m - 1                       ## m == INT64_MIN, representable: no trap here
  return -m                       ## +2^63 is NOT representable in i64 ⇒ §6.1 TRAP
}
