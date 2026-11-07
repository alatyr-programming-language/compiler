## e2e (#1499) CONTROL — `comptime for` ranges within the unroll budget still unroll, in each
## signedness: a `u64` range wholly above 2^63, a signed range from a negative bound, and a signed
## range whose upper bound is below its lower one (empty). The fix orders the range in its own type;
## these are the shapes that must not be refused or change their count.
##
## Measured on the parent (`f9ca474d`, native x86_64, omen): 42 on x86_64, aarch64, riscv64 and wasm,
## and the same here — the contrast for `reject_comptime_for_budget_u64`.
L : u64 = 9223372036854775808
H : u64 = 9223372036854775811
N : i64 = 0 - 1

main := fn() -> u64 {
  mut a : u64 = 0
  ## i - L is 0, 1, 2: a = 1 + 2 + 3 = 6
  comptime for i in L .. H { a = a + (i - L) + 1 }
  ## five iterations: a = 16
  comptime for j in 0 - 3 .. 2 { a = a + 2 }
  ## empty: 0 > -1 in `i64`
  comptime for k in 0 .. N { a = a + 100 }
  return a + 26
}
## expect: run 42
