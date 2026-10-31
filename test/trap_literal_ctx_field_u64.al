## e2e (#1268, control) — the context is the field's type, so `s.f = 5 - 6` with `f : u64` is an
## UNSIGNED subtraction whose value does not fit: it traps at run time and never stores the wrapped
## u64::MAX (which would return 7).
##
## Expected: a trap, 132 / 133 / 133 / 134 on x86_64 / aarch64 / riscv64 / wasm.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 133 / 133 / 134.

S := struct { f : u64 }

main := fn() -> i64 {
  mut s := S(f = 3)
  s.f = 5 - 6
  if s.f == 18446744073709551615 { return 7 }
  1
}
