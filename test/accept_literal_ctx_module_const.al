## e2e (#1268) — a module constant's ANNOTATION is the context of its literal-only initializer, as a
## local's is (Declarations §3.4, Types §9.1), and an unannotated one takes the native signed default:
## `M : i64 = 5 - 9223372036854775807 - 6` is i64 MIN, `N := 5 - 6` is -1. Neither is an unsigned
## subtraction that borrows (Concurrency §6.5: the guard follows the operand type).
##
## Expected: 42 on x86_64. aarch64 / riscv64 / wasm stay at 133 / 133 / 134 after this fix: they do
## not lay down a module constant's arithmetic initializer at all (even `K : i64 = 7 - 2` traps there),
## which is #923 / #590, not the literal's context, so e2e asserts x86_64 only until those land.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 133 / 133 / 134 (x86_64: the unsigned borrow guard traps).

M : i64 = 5 - 9223372036854775807 - 6
Z : i64 = 0 - 9223372036854775807 - 1
N := 5 - 6

main := fn() -> i64 {
  if M != Z { return 1 }
  if N != 0 - 1 { return 2 }
  42
}
## expect: run 42
