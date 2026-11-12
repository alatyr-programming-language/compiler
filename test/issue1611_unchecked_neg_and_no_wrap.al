## Comptime §1.1 (pin 1.9.0): `unchecked` does not change a constant expression, and a result outside
## the type's range is a compile error, never a wrap (I11). `(0 - 1) & 255` is 255 under the
## two's-complement reading (`&` over a negative operand is spec#91), which `i8` cannot hold either way.
## Sema does not reject it yet (tracked separately), so the program must at least not run on a wrapped
## value: the IR builder folds a literal-only expression only when its type holds the result.
## PR #1612's earlier head 4f7d62ab folded it inside `unchecked` by wrapping, so `a` was -1 and the
## program returned 3 on x86-ir, aarch64, riscv64 and wasm (measured on omen). Its merge base cf159743
## and the legacy x86_64 default trap on both heads, so this fixture fails only against 4f7d62ab.
main := fn() -> u64 {
  a : i8 = unchecked ((0 - 1) & 255)
  u64(a + 1 + 3)
}
## expect: trap
