## e2e (#1271) — an `unchecked` `+` in a `u32` `comptime for` range bound wraps at `u32`, as at run
## time: `K + 3` is 2, so the loop unrolls twice.
##
## Comptime §2.6 (spec v1.6.0): under `unchecked` the two's-complement wrap of `+ - *` evaluates
## normally.
##
## Expected: 42 on all four backends.
## Measured on the parent (#1261 rebased, native x86_64): the fold kept 2^32 + 2, x86_64 refused it
## with the unroll budget, and the twins trapped (133 / 133 / 134).
K : u32 = 4294967295

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. unchecked (K + 3) { c = c + 1 }
  if c != 2 { return 1 }
  return c + 40
}
