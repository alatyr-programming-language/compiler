## e2e (#1283) - the signed half of the same place: `y = 200` into `y : i8` is outside
## `-128..127`, and `y = 0 - 200` into `y : i8` is outside it on the lower bound. Both were accepted
## and the place held the truncated value. The in-range writes above them stay accepted.
main := fn() -> i64 {
  mut y : i8 = 0 - 128
  y = 127
  if i64(y) != 127 { return 1 }
  y = 200
  i64(y)
}
## expect: reject "type mismatch" "at line 8"
