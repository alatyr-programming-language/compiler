## e2e (#1271) — an `unchecked` `*` in an `i32` `comptime for` range bound wraps at `i32` before the
## next step: `A * A` is 0 in i32, so `0 * -2 / -1` is 0 and the loop never runs.
##
## Comptime §2.6 (spec v1.6.0): under `unchecked` the two's-complement wrap of `+ - *` evaluates
## normally, and `MIN / -1` is a diagnostic; here no `MIN` reaches the division.
##
## Expected: 40 on all four backends.
## Measured on the parent (#1261 rebased, native x86_64): the fold kept `A * A * -2` as i64's
## minimum, and the compiler died dividing it by -1 (SIGFPE, rc 136) for every backend.
A : i32 = 0 - 2147483647 - 1

main := fn() -> u64 {
  mut c : u64 = 0
  comptime for i in 0 .. unchecked ((A * A * (0 - 2)) / (0 - 1)) { c = c + 1 }
  return c + 40
}
