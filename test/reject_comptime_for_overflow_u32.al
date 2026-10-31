## e2e (#1234) — the overflow judgement uses the operation's own WIDTH: `K + 3` over a `u32` is
## 4294967298, which does not fit `u32`, so the bound is a LOCATED compile-time diagnostic (Comptime
## §2.6, spec v1.6.0), not the exact 64-bit sum.
##
## Expected: x86_64 refuses at line 14 with the overflow diagnostic; aarch64, riscv64 and wasm
## trap (133 / 133 / 134) until #1232 lands.
## Measured on the parent (#1229's head `833d9285`, native x86_64): x86_64 refused only through the
## unroll budget ("comptime-for range exceeds the unroll budget"), not as an overflow; the twins
## trapped (133 / 133 / 134).
K : u32 = 4294967295

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. K + 3 { c = c + 1 }
  return c + 7
}
