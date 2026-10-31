## e2e (#1268) — a parameter typed by a TYPE parameter takes the type the call passes for it as its
## argument's context: in `lt(i64, 5 - 6, 1)` the `5 - 6` is -1 at `i64`, and `-1 < 1` holds.
##
## Expected: 42 on x86_64, aarch64, riscv64 and wasm.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 133 / 133 / 134 (the unsigned borrow guard traps).

lt := fn(T : type, a : T, b : T) -> bool { return a < b }

main := fn() -> i64 {
  if lt(i64, 5 - 6, 1) { return 42 }
  1
}
