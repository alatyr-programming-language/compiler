## e2e (#1268) — a `print` hole gives its argument no type, so a literal-only argument takes the
## documented default, the native signed integer (Types §9.1): `5 - 6` prints -1, never a borrow trap.
##
## Expected: prints `-1 -7` and exits 42 on x86_64, aarch64, riscv64 and wasm.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 133 / 133 / 134 (the unsigned borrow guard traps).

main := fn() -> i64 {
  print("{} {}\n", 5 - 6, 3 - 10)
  42
}
