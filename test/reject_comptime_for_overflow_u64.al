## e2e (#1234) — a checked `+` that overflows `u64` in a `comptime for` range bound is a LOCATED
## compile-time diagnostic, never a wrapped bound.
##
## Comptime §2.6 (spec v1.6.0): the evaluator runs the run-time checked-guard family, and a failing
## guard is a located compile-time diagnostic; no wrapped value is materialized in its place.
##
## Expected: x86_64 refuses at line 15 with the overflow diagnostic; aarch64, riscv64 and wasm
## trap (133 / 133 / 134) until the twins' compile-time refusal (#1232) lands.
## Measured on the parent (#1229's head `833d9285`, native x86_64): all four backends built it, `K + 2`
## wrapped to 1, the loop unrolled once and the program exited 8.
K : u64 = 18446744073709551615

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. K + 2 { c = c + 1 }
  return c + 7
}
