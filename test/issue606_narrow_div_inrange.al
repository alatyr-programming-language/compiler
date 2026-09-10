## The non-vacuity control for the narrow `MIN / -1` trap (Concurrency §6.1): a guard that fires on
## every narrow signed divide, or on the minimum dividend alone, would satisfy every trap fixture in
## this family while destroying ordinary division. The cross-target sweeps cannot catch that — they
## accept a trap as a permitted outcome for any program — so the assertion has to be a VALUE, and
## the row is registered on all four backends for exactly that reason.
##
## Each case is a divide the checked set does NOT cover, and each contributes a distinct digit so a
## single wrong arm is identifiable from the exit code rather than only from a mismatch:
##   1  the minimum dividend by a divisor that is not -1     (-128 / 2   = -64)
##   2  an ordinary negative narrow divide                   (-100 / 3   = -33)
##   4  -1 as the DIVIDEND rather than the divisor           (-1 / -1    = 1)
##   8  the `i16` minimum by 2                               (-32768 / 2 = -16384)
##  16  unsigned narrow division, which can never overflow   (200 / 3    = 66)
##  32  `MIN % -1`, the remainder, whose result 0 is representable and must NOT trap
## The sum 63 is the pass value; any missing arm subtracts its own digit.
main := fn() -> u64 {
  mut acc : u64 = 0
  a : i8 = 0 - 128
  two : i8 = 2
  if a / two == 0 - 64 { acc = acc + 1 }
  b : i8 = 0 - 100
  three : i8 = 3
  if b / three == 0 - 33 { acc = acc + 2 }
  m1 : i8 = 0 - 1
  if m1 / m1 == 1 { acc = acc + 4 }
  c : i16 = 0 - 32768
  two16 : i16 = 2
  if c / two16 == 0 - 16384 { acc = acc + 8 }
  u : u8 = 200
  three8 : u8 = 3
  if u / three8 == 66 { acc = acc + 16 }
  if a % m1 == 0 { acc = acc + 32 }
  return acc
}
