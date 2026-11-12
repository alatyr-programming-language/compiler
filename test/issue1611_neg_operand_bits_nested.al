## Comptime §1.1 (pin 1.9.0) leaves open what `&`, `|` and `^` give over a negative operand (spec#91).
## Here the negative operand sits in a NESTED bitwise step: the outer `| 0` sees only 255, which the
## inner `(0 - 1) & 255` would give under a two's-complement reading. The IR builder's literal-only
## bitwise fold (#1611) must check every bitwise step of the tree, not only the top one: PR #1612's
## earlier head a733b92d folded it to 255 and the program returned 55 on x86-ir, aarch64, riscv64 and
## wasm (measured on omen). Built as written, as before #1612, `0 - 1` traps at `u8` on every path.
## Its sibling: issue1611_neg_operand_bits_top.
main := fn() -> u64 {
  a : u8 = ((0 - 1) & 255) | 0
  u64(a) - 200
}
## expect: trap
