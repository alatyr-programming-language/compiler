## Comptime §1.1 (pin 1.9.0) leaves open what `&`, `|` and `^` give over a negative operand (spec#91),
## so the compiler must not choose a value for `(0 - 1) & 255`. This fixture pins that the IR builder's
## literal-only bitwise fold (#1611) does not fold it: PR #1612's earlier head a733b92d folded it to 255
## and the program returned 55 on x86-ir, aarch64, riscv64 and wasm (measured on omen).
## The expression is built as written, as before #1612: `0 - 1` is checked at `u8` and traps, on every
## path. The trap is the overflow, not a decision about spec#91.
## Its sibling: issue1611_neg_operand_bits_nested.
main := fn() -> u64 {
  a : u8 = (0 - 1) & 255
  u64(a) - 200
}
## expect: trap
