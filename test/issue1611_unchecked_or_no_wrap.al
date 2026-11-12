## Comptime §1.1 (pin 1.9.0): `unchecked` does not change a constant expression, and a result outside
## the type's range is a compile error, never a wrap (I11). `128 | 1` is 129, which `i8` cannot hold.
## Sema does not reject it yet (#1627). This fixture pins only that the IR builder's literal-only
## bitwise fold (#1611) does not wrap it: PR #1612's earlier head 4f7d62ab folded it to -127, and the
## program returned 3 on x86-ir, aarch64, riscv64 and wasm (measured on omen).
## The trap is NOT a refusal of the program. Without a wrapping fold the builder refuses the operand
## `128` at `i8`, the function falls back, and `a` holds 129, outside its type's range, on every path
## (before #1612 too; #1627). The trap is the overflow in `a + 127 + 3`.
## Its siblings: issue1611_unchecked_and_no_wrap, issue1611_unchecked_neg_and_no_wrap.
main := fn() -> u64 {
  a : i8 = unchecked (128 | 1)
  u64(a + 127 + 3)
}
## expect: trap
