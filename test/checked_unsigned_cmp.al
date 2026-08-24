## I11 / signedness — UNSIGNED ordering comparison across 2^63. The non-inline binary-op fallback
## once emitted SIGNED setcc (`setl`/…) unconditionally, so a `u64`/`usize` comparison whose operands
## straddle 2^63 read the high-bit operand as NEGATIVE and evaluated WRONG. With both operands PROVABLY
## unsigned the fallback now emits the UNSIGNED setcc (`setb`/`seta`/`setbe`/`setae`). This program
## checks all four orderings across the boundary (all must hold) AND that a genuinely SIGNED comparison
## (`i64 -1 < 0`) still uses the signed path. Every correct result contributes to the sum 42; any wrong
## comparison (a regression either way) makes it != 42. x86_64 (registered run_x86; other backends keep
## the always-signed ordering pending their own fix, so this is sweep-excluded).
main := fn() -> u64 {
  a : u64 = 0
  b : u64 = 18446744073709551615
  mut r : u64 = 0
  ## UNSIGNED across 2^63 — the fixed cases (b has bit 63 set; signed would read it negative).
  if a < b { r = r + 7 }      ## 0 < MAX  → true
  if b > a { r = r + 7 }      ## MAX > 0  → true
  if a <= b { r = r + 7 }     ## 0 <= MAX → true
  if b >= a { r = r + 7 }     ## MAX >= 0 → true
  ## NEGATIVE cases — must be FALSE under correct unsigned semantics (would wrongly fire if signed).
  if b < a { r = r + 100 }    ## MAX < 0  → false
  if a > b { r = r + 100 }    ## 0 > MAX  → false
  ## Boundary equality still correct.
  if b <= b { r = r + 7 }     ## MAX <= MAX → true
  ## SIGNED path intact: -1 < 0 is TRUE (signed), and 0 < -1 is FALSE.
  s : i64 = 0 - 1
  t : i64 = 0
  if s < t { r = r + 7 }      ## -1 < 0 → true (signed)
  if t < s { r = r + 100 }    ## 0 < -1 → false (signed)
  return r
}
