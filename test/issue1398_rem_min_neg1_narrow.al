## #1398 — NON-VACUITY for the native-width `MIN % -1` fix: the NARROW widths must still answer `0`.
##
## Concurrency §6.1 (spec v1.6.0) gives a checked `MIN % -1` the value `0` at every width, and appendix
## §2 states it per arch. A narrow `%` is computed at 64 bits and narrowed back, so its dividend never
## reaches the 64-bit minimum and no guard is owed at all: these cases passed on the parent and must
## still pass on the head. They are what says the fix restricted the `MIN / -1` guard to `/` rather than
## deleting it — a `%` whose guard was dropped wholesale, or a divide that stopped computing, would fail
## the native-width fixture (`issue1398_rem_min_neg1`) and the trap fixtures, but only these digits catch
## a narrow `%` that stopped narrowing or an unsigned divide that took the signed arm.
##
##   1   `i8`  `-128 % -1` == 0
##   2   `i16` `-32768 % -1` == 0
##   4   `i32` `-2147483648 % -1` == 0
##   8   unsigned narrow `200 % 3` == 2 (the unsigned arm, runtime divisor)
##  16   unsigned narrow `200 % 1` == 0 (a divisor of 1 on the unsigned path)
## The sum 31 is the pass value; any missing arm subtracts its own digit.
rem8 := fn(a : i8, b : i8) -> i8 { return a % b }
rem16 := fn(a : i16, b : i16) -> i16 { return a % b }
rem32 := fn(a : i32, b : i32) -> i32 { return a % b }
remu8 := fn(a : u8, b : u8) -> u8 { return a % b }
main := fn() -> u64 {
  mut acc : u64 = 0
  n8 : i8 = 0 - 1
  if rem8(0 - 128, n8) == 0 { acc = acc + 1 }
  n16 : i16 = 0 - 1
  if rem16(0 - 32768, n16) == 0 { acc = acc + 2 }
  n32 : i32 = 0 - 1
  if rem32(0 - 2147483648, n32) == 0 { acc = acc + 4 }
  three : u8 = 3
  if remu8(200, three) == 2 { acc = acc + 8 }
  one : u8 = 1
  if remu8(200, one) == 0 { acc = acc + 16 }
  return acc
}
## expect: run 31
