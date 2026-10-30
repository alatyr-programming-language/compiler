## e2e (#1233) — `MIN % -1` in a `comptime for` range bound is a LOCATED compile-time diagnostic, under
## `unchecked` too (Comptime §2.6, spec v1.6.0: hardware-defined, so it remains a diagnostic).
##
## Expected: x86_64 refuses at line 14 with the `MIN / -1` diagnostic; aarch64, riscv64 and wasm trap
## (133 / 133 / 134) until #1232 lands.
## Measured on the parent (#1234's head `be44a601`, stacked on #1229; native x86_64): the compiler
## itself died with SIGFPE (rc 136, no message) on x86_64, and so did the aarch64, riscv64 and wasm
## emit steps.
K : i64 = 0 - 9223372036854775807 - 1
D : i64 = 0 - 1

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. 3 + unchecked (K % D) { c = c + 1 }
  return c + 40
}
