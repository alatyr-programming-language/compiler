## I11 / CG-8 + CG-13, Concurrency §6.1: `MIN / -1` is the DIVISION-OVERFLOW member of the
## checked-overflow set at EVERY signed width, not only at `i64`. For `i8` the minimum is -128 and
## the quotient +128 is not representable, so the family's ONE direct inline trap is due BEFORE the
## divide — `ud2` on x86_64 (SIGILL, exit 132), `brk #0` on aarch64 (133), `ebreak` on riscv64 (133),
## `unreachable` on wasm (134). `checked_div_min_neg1` is the `i64` dual.
##
## PARENT BEHAVIOUR (all four backends, exit 60): the guard compared the dividend against the
## 64-bit INT64_MIN only, so a narrow dividend never matched it and the divide produced 128 — a
## value OUTSIDE `i8` living in an `i8` binding. The `q <= 127` test below is the guard a caller
## writes against the real result, and it holds for EVERY value of the type; it was not taken,
## which is the shape of a guard defeated by its own operand rather than by its own logic.
##
## Exit status is modulo 256, so the arms distinguish the three readings by a SECOND signal rather
## than by the code alone: 60 = a quotient above the `i8` maximum reached the binding (for this
## dividend and divisor that value can only be +128), 61 = the 8-bit wrap -128, 62 = any other
## in-range quotient. No arm compares against a literal outside `i8`, so the fixture does not
## depend on out-of-range literals being accepted (#602's family).
##
## Both operands arrive through runtime bindings (`0 - 1` is a subtraction, not a positive literal),
## so no backend may elide the guard as provably unnecessary.
main := fn() -> u64 {
  v : i8 = 0 - 128
  d : i8 = 0 - 1
  q := v / d
  if q <= 127 {
    if q == 0 - 128 { return 61 }
    return 62
  }
  return 60
}
