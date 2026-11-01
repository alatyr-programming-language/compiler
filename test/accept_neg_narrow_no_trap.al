## #1049 / #633 — the narrow negations that must NOT trap after the guard follows the operand type.
##
## Concurrency (spec v1.6.0) §6.5: unary `−` over an unsigned operand is the negation modulo 2^N, a
## representable value; §6.3: "an unsigned negation or division has no overflow member". §6.2: a
## programmer who wants the wrap writes `unchecked`. A signed negation of anything but MIN fits.
##
## Each line returns its own code if it traps or answers wrong; the companion trap fixtures
## (`trap_neg_min_i8.al`, `_i16`, `_i32`) pin the MIN case. Expected: exit 42, no trap.
main := fn() -> i64 {
  mut s : i8 = -127
  if -s != 127 { return 1 }                ## in range: 127 fits in i8
  mut u : u8 = 5
  n : u8 = -u                              ## 256 - 5, unsigned: no overflow member (§6.3)
  if n != 251 { return 2 }
  mut z : u8 = 0
  if -z != 0 { return 3 }                  ## 0 negates to 0
  mut m : i8 = -127
  m = m - 1                                ## i8 MIN
  w : i8 = unchecked -m                    ## the programmer's grant: wraps to MIN (§6.2)
  if w != m { return 4 }
  mut h : i16 = 300
  if 0 + h != 300 { return 5 }             ## zero-left `+` and `*` cannot overflow
  if 0 * h != 0 { return 6 }
  mut q : u32 = 7
  if -q != 4294967289 { return 7 }         ## 2^32 - 7
  return 42
}
## expect: run 42
