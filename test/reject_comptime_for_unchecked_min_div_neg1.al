## e2e (#1233) — `MIN / -1` in a `comptime for` range bound is a LOCATED compile-time diagnostic, under
## `unchecked` too, and the compiler never performs the division.
##
## Comptime §2.6 (spec v1.6.0): inside `unchecked` the evaluator drops guards as run time does, except
## that an operation whose unchecked behaviour is hardware-defined (`MIN / -1` and `MIN % -1` among
## them) remains a diagnostic at comptime.
##
## Expected: x86_64 refuses at line 16 with the `MIN / -1` diagnostic; aarch64, riscv64 and wasm trap
## (133 / 133 / 134) until the twins' compile-time refusal (#1232) lands.
## Measured on the parent (#1234's head `be44a601`, stacked on #1229; native x86_64): the compiler
## itself died with SIGFPE (rc 136, no message) on x86_64, and so did the aarch64, riscv64 and wasm
## emit steps.
main := fn() -> u64 {
  mut c : u64 = 0
  ## two literal-only bounds take the native signed default, i64 (Types §9.1): the dividend is MIN
  comptime for i in 0 .. unchecked ((0 - 9223372036854775807 - 1) / (0 - 1)) { c = c + 1 }
  return c + 40
}
