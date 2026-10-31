## e2e (#1268) — an array type `[T; N]` is the context of each element of an array literal it
## annotates, local or module-level: `[5 - 6, 3, 2 - 9]` under `[i64; 3]` holds -1 and -7.
##
## Expected: 42 on x86_64, aarch64, riscv64 and wasm.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 42 / 42 / 42 (x86_64's unsigned borrow guard traps).

G : [i64; 2] = [5 - 6, 0 - 1]

main := fn() -> i64 {
  a : [i64; 3] = [5 - 6, 3, 2 - 9]
  if a[0] != 0 - 1 { return 1 }
  if a[2] != 0 - 7 { return 2 }
  if G[0] != 0 - 1 { return 3 }
  if G[1] != 0 - 1 { return 4 }
  42
}
