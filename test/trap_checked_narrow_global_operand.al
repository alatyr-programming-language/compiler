## e2e (#1272) — a CHECKED `+` whose left operand is a global `i32` const and whose right operand is
## an expression traps when the sum does not fit `i32`; it never stores 2^31 in an `i32`.
##
## I11 / CG-8 (spec v1.6.0): a checked `+` that overflows its type traps.
##
## Expected: 132 on x86_64 (ud2); 133 / 133 / 134 on aarch64 / riscv64 / wasm.
## Measured on the parent (main 930c4e17, native x86_64): x86_64 stored 2^31 and exited 40; the twins
## trapped (133 / 133 / 134).
A : i32 = 2147483647

main := fn() -> u64 {
  k : i32 = 0
  x : i32 = A + (k + 1)
  if x < 0 { return 1 }
  return 40
}
