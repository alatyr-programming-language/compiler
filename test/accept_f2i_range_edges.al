## #997 companion — the float→int conversions that must NOT trap, at the edges of each range.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
## A value whose truncation fits is in range even when the float itself is not an integer: `u8(-0.9)`
## is 0 and `i8(-128.9)` is -128. Inside `unchecked` the out-of-range result is hardware-defined, so
## it must not trap; this fixture does not assert its value.
##
## `u64` at or above 2^63 is the other half of #997. Measured on x86_64 at origin/main 55fa477,
## this fixture exits 8: `u64(0.75 * 2^64)` answered the wrong value, because the signed `cvttsd2si`
## returns 2^63 for any value above i64 MAX.
##
## Each check returns its own code if it fails. Expected: exit 42, no trap (wasm: 134 at check 13).
main := fn() -> u64 {
  mut one : f64 = 1.0                       ## run-time 1.0, so nothing folds at compile time
  if i8(127.9 * one) != 127 { return 1 }
  if i8(0.0 - 128.9 * one) != 0 - 128 { return 2 }
  if u8(255.9 * one) != 255 { return 3 }
  if u8(0.0 - 0.9 * one) != 0 { return 4 }
  if i16(0.0 - 32768.5 * one) != 0 - 32768 { return 5 }
  if u32(4294967295.5 * one) != 4294967295 { return 6 }
  if i32(0.0 - 2147483648.0 * one) != 0 - 2147483648 { return 7 }
  t := 4294967296.0 * one
  if u64(t * t * 0.75) != 13835058055282163712 { return 8 }         ## 0.75 * 2^64, above 2^63
  if u64(t * t * 0.5) != 9223372036854775808 { return 9 }           ## exactly 2^63
  if u64(t * t * 0.4) != 7378697629483821056 { return 10 }          ## below 2^63: the signed path
  if i64(0.0 - t * t * 0.5) != 0 - 9223372036854775807 - 1 { return 11 }   ## exactly i64 MIN
  if i64(0.0 - 3.9 * one) != 0 - 3 { return 12 }                    ## toward zero
  mut z : f64 = 0.0
  w := unchecked u64(z / z)                 ## NaN, unchecked: hardware-defined (traps on wasm)
  if w == 1 { return 13 }                  ## (keeps `w` live; the hardware never answers 1)
  return 42
}
