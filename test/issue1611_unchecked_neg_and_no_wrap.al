## Comptime §1.1 (pin 1.9.0): `unchecked` does not change a constant expression, and a result outside
## the type's range is a compile error, never a wrap (I11). `(0 - 1) & 255` is 255 under the
## two's-complement reading (`&` over a negative operand is spec#91), which `i8` cannot hold either way.
## Sema does not reject it yet (#1627). This fixture pins only that the IR builder's literal-only
## bitwise fold (#1611) does not wrap it: PR #1612's earlier head 4f7d62ab folded it to -1, and the
## program returned 3 on x86-ir, aarch64, riscv64 and wasm (measured on omen).
## The trap is NOT a refusal of the program. Without a wrapping fold the builder refuses the operand
## `255` at `i8`, the function falls back, and `a` holds 255, outside its type's range, on every path
## (before #1612 too; #1627). The trap is the overflow in `a + 1 + 3`.
main := fn() -> u64 {
  a : i8 = unchecked ((0 - 1) & 255)
  u64(a + 1 + 3)
}
## expect: trap
