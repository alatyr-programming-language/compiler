## e2e (#1268) — the constructor form `T(v)` refines a literal's type as an annotation does (Types §9.2),
## so a scalar `T` is the context of a literal-only `v`: `i64(5 - 6)` is -1 at `i64`, `i8(0 - 128)` is
## -128 at `i8`. Never an unsigned subtraction that borrows (Concurrency §6.5).
##
## Expected: 42 on x86_64, aarch64, riscv64 and wasm.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 133 / 133 / 134 (the unsigned borrow guard traps on `5 - 6`).

main := fn() -> i64 {
  w := i64(5 - 6)
  z := i64(0 - 1)
  b := i8(0 - 128)
  if w != 0 - 1 { return 1 }
  if z != 0 - 1 { return 2 }
  if i64(b) != 0 - 128 { return 3 }
  42
}
## expect: run 42
