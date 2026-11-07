## e2e (#1283) - the signed half of the same place: `y = 200` into `y : i8` is outside
## -128..127, and it was accepted with the place left holding the truncated value. The
## in-range writes above it stay accepted, including the lower bound AT its edge (`0 - 128`).
## NOTE: the lower bound BEYOND the edge (`y = 0 - 200`) is NOT pinned here; it is the same
## predicate on the other side and is called out as a follow-up on #1283, so this file does not
## claim to cover it.
main := fn() -> i64 {
  mut y : i8 = 0 - 128
  y = 127
  if i64(y) != 127 { return 1 }
  y = 200
  i64(y)
}
## expect: reject "type mismatch" "at line 11"
