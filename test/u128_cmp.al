## e2e — ROADMAP §8.4 part 1b, TYP-10 slice C: COMPARISON operators on the prelude `u128 ≡
## uint(128)` (Types §3/§7, TYP-2 / TYP-10 / D23 / D24; operators.md OP-1). The six comparisons
## (`==`/`!=`/`<`/`<=`/`>`/`>=`) are `@inline` GENERIC operators over the comptime value parameter
## N (lib/base/u128.al), used by BARE prelude name. Ordering is hi-word-to-lo-word lexicographic
## UNSIGNED — `<` is computed COMPARISON-FREE (the `a - b` borrow ripple's missing final carry IS
## `a < b`), `==` is the OR of the per-word XORs, and `!=`/`>`/`<=`/`>=` are the nested generic
## routes (`==`/`<` over the same instance). No signed-`setcc` pitfall is reachable by construction.
##
## Cases straddle the word boundary so a hi-first bug (or a low-word-only bug) is caught:
##   [0, 1]   >  [MAX, 0]   — the HIGH word decides, the low word would say the opposite (MAX>0)
##   [10, 5]  == [10, 5]    — full equality
##   [10, 5]  <  [11, 5]    — tie on the high word, the low word decides
##   [10, 5]  <= [10, 5]    — non-strict at equality
## 42 = 10 + 6 + 20 + 6 built by selecting through each comparison; any single mis-compare misses it.
main := fn() -> u64 {
  big  := u128(words = [0, 1])
  smax := u128(words = [18446744073709551615, 0])
  a    := u128(words = [10, 5])
  b    := u128(words = [10, 5])
  c    := u128(words = [11, 5])

  mut acc : u64 = 0
  if big > smax { acc = acc + 10 }        ## hi-first: 1>0 despite low word MAX>0 -> +10
  if big >= smax { acc = acc + 6 }        ## >= same -> +6  (acc=16)
  if a == b { acc = acc + 20 }            ## full eq -> +20  (acc=36)
  if a != c { acc = acc + 3 }             ## low word differs -> +3 (acc=39)
  if a < c { acc = acc + 2 }              ## tie on hi, 10<11 -> +2 (acc=41)
  if a <= b { acc = acc + 1 }             ## non-strict eq -> +1 (acc=42)
  if smax > big { acc = acc + 100 }       ## MUST be false (hi 0<1) -> no add
  if c < a { acc = acc + 100 }            ## MUST be false -> no add
  return acc
}
