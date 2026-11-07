## e2e (#1499) — a `u64` `comptime for` range that CROSSES 2^63 unrolls its exact count, and a `u64`
## range whose lower bound is above 2^63 and whose upper bound is small is empty. Both are within the
## unroll budget. The bounds' `i64` patterns straddle the sign bit, so a signed `hi - lo` overflows.
##
## Types §3.2 / Concurrency §6.5 (spec v1.8.0): the operands are `u64`, so the range is ordered
## unsigned. Measured on the parent (`f9ca474d`, native x86_64, omen): the compiler itself died with
## SIGILL (rc 132, its own checked subtraction trapping) on x86_64, aarch64, riscv64 and wasm emission.
L : u64 = 9223372036854775806
H : u64 = 9223372036854775810
K : u64 = 9223372036854775813

main := fn() -> u64 {
  mut a : u64 = 0
  ## i - L is 0, 1, 2, 3 across 2^63: a = 1 + 2 + 3 + 4 = 10
  comptime for i in L .. H { a = a + (i - L) + 1 }
  ## empty: K > 5 as a `u64`
  comptime for j in K .. 5 { a = a + 100 }
  return a + 32
}
## expect: run 42
