## #1374 companion — the in-range edges `accept_f2i_range_edges` does not reach, which the checked
## conversion must NOT trap on: the `i16`/`u16`/`i32`/`u32` maxima, a negative fraction into an
## unsigned type, and `usize`/`isize`/`u64`/`i64` one f64 step inside their bounds.
##
## Concurrency §7.7 (spec v1.6.0): float→int rounds toward zero and traps only when the result is
## outside the integer's range, or on a NaN. Each bound of `lower_layout::f2i_bounds` is the first
## f64 OUTSIDE the range, so these values, one step inside, are in range.
##
## Measured on #1222's head c4058737: 42 on every backend (the twins had no guard to misplace).
## Each check returns its own code if it fails. Expected: exit 42, no trap, on every backend.
main := fn() -> u64 {
  mut one : f64 = 1.0                       ## run-time 1.0, so nothing folds at compile time
  if i16(32767.9 * one) != 32767 { return 1 }
  if u16(65535.9 * one) != 65535 { return 2 }
  if u16(0.0 - 0.9 * one) != 0 { return 3 }
  if i32(2147483647.9 * one) != 2147483647 { return 4 }
  if u32(0.0 - 0.9 * one) != 0 { return 5 }
  if i8(0.0 - 128.9 * one) != 0 - 128 { return 6 }
  t := 4294967296.0 * one
  if usize(t * t * 0.999999) != 18446725626965477376 { return 7 }
  if isize(0.0 - t * t * 0.5) != 0 - 9223372036854775807 - 1 { return 8 }   ## exactly isize MIN
  if u64(t * t * 0.9999999999999999) != 18446744073709549568 { return 9 }  ## the last f64 below 2^64
  if i64(t * t * 0.4999999999999999) != 9223372036854773760 { return 10 }   ## 2^63 - 2048
  return 42
}
## expect: run 42
