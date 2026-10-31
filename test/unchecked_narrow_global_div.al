## e2e (#1272) — an `unchecked` `*` over a global `i32` const wraps at `i32` before the division:
## `H * H` is 2^60, which is 0 in i32, so `0 * -8 / -1` is 0.
##
## Types §4 value model and I11 (spec v1.6.0): an `unchecked` `+ - *` takes the two's-complement wrap
## at its operand type's width; nothing here divides `MIN` by -1.
##
## Expected: 40 on all four backends.
## Measured on the parent (main 930c4e17, native x86_64): x86_64 computed the product at 64 bits,
## reached `idivq` with i64::MIN / -1 and died with SIGFPE (136).
H : i32 = 1073741824

main := fn() -> u64 {
  x : i32 = unchecked ((H * H * (0 - 8)) / (0 - 1))
  if x != 0 { return 1 }
  return 40
}
