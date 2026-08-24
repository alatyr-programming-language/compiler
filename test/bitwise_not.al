## e2e — unary prefix `~` (bitwise NOT / one's complement), Grammar §130 + the bitwise family
## `& | ^ ~`. Previously a SILENT MISCOMPILE: `~s` parsed as `s` (the `~` was silently DROPPED, no
## complement emitted). Now desugared to `x ^ (-1)` (XOR with the all-ones word), reusing the
## existing bitwise-xor lowering on every backend. Each clause is load-bearing — if `~` were dropped
## the result would NOT be 42 (and `a - b` would underflow-trap).
##  - `~0`  = all-ones (2^64-1); `& 42` = 42        (dropped: 0 & 42 = 0)
##  - `(~0) - (~5)` = (2^64-1) - (2^64-6) = 5        (dropped: 0 - 5 underflows)
##  - `~~x == x`  (double complement is identity)
## Total: 42 + (5 - 5) + (7 - 7) = 42.
main := fn() -> u64 {
  s : u64 = 0
  t := ~s              ## all-ones
  m := t & 42          ## 42

  five : u64 = 5
  a := ~s              ## 2^64-1
  b := ~five           ## 2^64-6
  d := a - b           ## 5  (complement drives both operands)

  x : u64 = 7
  y := ~~x             ## 7  (identity)

  m + (d - five) + (y - x)
}
