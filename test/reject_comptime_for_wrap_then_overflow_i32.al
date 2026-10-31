## e2e (#1271) — an `unchecked` `+` in an `i32` `comptime for` range bound wraps at `i32`, so the
## CHECKED `-` after it overflows `i32` and is a LOCATED compile-time diagnostic, never a wrong bound.
##
## Comptime §2.6 (spec v1.6.0): under `unchecked` the two's-complement wrap of `+ - *` evaluates
## normally; a failing checked guard is a located compile-time diagnostic.
##
## Expected: x86_64 refuses at line 16 with the overflow diagnostic (`unchecked (K + 1)` is MIN, and
## `MIN - 2147483600` overflows i32); aarch64, riscv64 and wasm trap (133 / 133 / 134) until the
## twins' compile-time refusal (#1232) lands.
## Measured on the parent (#1261 rebased, native x86_64): all four backends built it, the fold kept
## `K + 1` as 2^31, and the program exited 48.
K : i32 = 2147483647

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. unchecked (K + 1) - 2147483600 { c = c + 1 }
  return c
}
