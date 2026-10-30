## e2e (#1234) — a checked `+` that overflows `i64` in a `comptime for` range bound is a LOCATED
## compile-time diagnostic, never a wrapped bound (Comptime §2.6, spec v1.6.0).
##
## Expected: x86_64 refuses at line 12 with the overflow diagnostic; aarch64, riscv64 and wasm
## trap (133 / 133 / 134) until #1232 lands.
## Measured on the parent (#1229's head `833d9285`, native x86_64): all four backends built it, `K + 1`
## wrapped to MIN, the loop unrolled zero times and the program exited 7.
K : i64 = 9223372036854775807

main := fn() -> i64 {
  mut c : i64 = 0
  comptime for i in 0 .. K + 1 { c = c + 1 }
  return c + 7
}
