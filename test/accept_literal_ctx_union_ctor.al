## e2e (#1268) — a raw union member's declared type is the context of its constructor's argument,
## as an enum payload's is: `U.s(5 - 6)` stores -1 as `i64`, read back through `u` as u64::MAX.
##
## Expected: 42 on x86_64. aarch64 / riscv64 / wasm stay at 133 / 133 / 134 after this fix: their
## `5 - 6` is now the signed subtraction, but reading the member `x.u` is still a fail-loud field-access
## stub there (#1187), so e2e asserts x86_64 only until that lands.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 133 / 133 / 134 (x86_64: the unsigned borrow guard traps).

U := union { s(i64), u(u64) }

main := fn() -> i64 {
  x := U.s(5 - 6)
  v := unchecked (x.u)
  if v == 18446744073709551615 { return 42 }
  7
}
## expect: run 42
