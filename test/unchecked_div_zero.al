## I11 / CG-7 scoping: an `unchecked` scope DROPS the div-by-zero guard. On aarch64 a raw
## `sdiv x, x, 0` returns 0 (no trap), so this program exits 0 — proving the guard is
## comptime-absent inside `unchecked` (the aarch64 `A64_CHK` false path). Registered aarch64-
## only: the raw ISA div-by-zero value is backend-specific (riscv64 yields all-ones, x86_64
## faults in hardware regardless), so 0 is a clean assertion only on aarch64.
divide := fn(a : i64, b : i64) -> i64 { return unchecked (a / b) }
main := fn() -> i64 { return divide(42, 0) }
