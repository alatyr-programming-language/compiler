## I11 / signedness — UNSIGNED ordering comparison across 2^63, exercised on ALL backends. The a64
## (`slt`-style `cset lt/gt/le/ge`) and rv64 (`slt`) backends once emitted SIGNED ordering
## UNCONDITIONALLY, so a `u64`/`usize` comparison whose operands straddle 2^63 read the high-bit
## operand as NEGATIVE and evaluated WRONG (`0 < u64::MAX` was FALSE) — the same latent silent
## miscompile the x86_64 fallback carried. With BOTH operands PROVABLY unsigned the backends now emit
## the UNSIGNED condition (a64 `lo`/`hi`/`ls`/`hs`; rv64 `sltu`-based). This program sums 7 for each of
## six correct unsigned orderings (→ 42) and adds 100 for any comparison that fires only under the
## broken SIGNED reading, so a regression on ANY backend shows as a NON-42 (sweep-visible) exit.
## Registered with plain `run` (NOT run_x86) so the a64/rv64 sweeps exercise it across the boundary.
main := fn() -> u64 {
  a : u64 = 0
  b : u64 = 18446744073709551615
  mut r : u64 = 0
  ## UNSIGNED across 2^63 — the fixed cases (b has bit 63 set; signed would read it negative).
  if a < b { r = r + 7 }      ## 0 < MAX   → true
  if b > a { r = r + 7 }      ## MAX > 0   → true
  if a <= b { r = r + 7 }     ## 0 <= MAX  → true
  if b >= a { r = r + 7 }     ## MAX >= 0  → true
  ## Boundary equality still correct under the unsigned condition.
  if b <= b { r = r + 7 }     ## MAX <= MAX → true
  if a >= a { r = r + 7 }     ## 0 >= 0    → true
  ## NEGATIVE cases — FALSE under correct unsigned semantics; would WRONGLY fire if read as signed.
  if b < a { r = r + 100 }    ## MAX < 0   → false (signed miscompile → +100)
  if a > b { r = r + 100 }    ## 0 > MAX   → false (signed miscompile → +100)
  return r
}
