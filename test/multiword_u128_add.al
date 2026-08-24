## e2e — FIRST INCREMENT of the non-native-width integer capability (Types §3, TYP-2 / D23 / D24;
## spec/20-types.md §7 "Wider-than-native named integers"; operators.md OP-1). A wider-than-native
## unsigned integer is an ORDINARY LIBRARY type: `u128` on a 64-bit host is a multiword value of TWO
## native u64 words {lo, hi}, with library-defined, carry-propagating arithmetic and VISIBLE cost,
## built by the §5 operators-as-library machinery (OP-1: `+` is a library function; the multiword
## `+` selects its mode) — like the 2-word `Vec2 +` in operator_vec2.al, but WITH CARRY.
##
## Each word adds with wrapping (modular) semantics: the checked overflow guard (I11/CG-8) is dropped
## per field via `unchecked`, else the low-word carry would trap instead of propagate. The carry OUT
## of the low-word add is recovered by the half-sum identity
##   ((lo_a>>1) + (lo_b>>1) + ((lo_a & lo_b) & 1)) >> 63
## i.e. bit 63 of the reduced-width sum — using only `shr`/`+`/`&`. (The spec's stated recipe is the
## simpler `sum_lo < a.lo`, but unsigned `<` on operands straddling 2^63 is miscompiled as a SIGNED
## compare in non-inline code today — see the session report; the half-sum form is equivalent and
## unaffected.) The `+` is `@inline` so the 2-word result is delivered through the struct-return
## convention and the carry runs in the routing-correct inline context (as operator_vec2.al relies on).
##
## Two adds exercise BOTH carry decisions:
##   carrying   : {lo=U64_MAX, hi=0} + {lo=1,  hi=0}  = {lo=0,  hi=1}   (lo wraps -> +1 into hi)
##   non-carry  : {lo=5,       hi=6} + {lo=10, hi=20} = {lo=15, hi=26}  (lo does NOT wrap -> +0)
## 42 = r.lo + r.hi + s.lo + s.hi = 0 + 1 + 15 + 26. A NEVER-carry bug -> r.hi=0 -> 41; an
## ALWAYS-carry bug -> s.hi=27 -> 43. Only the correct carry yields 42.
U128 := struct { lo : u64, hi : u64 }

@inline + := fn(a : U128, b : U128) -> U128 {
  U128(
    lo = unchecked { a.lo + b.lo },
    hi = unchecked { a.hi + b.hi + (unchecked { a.lo.shr(1) + b.lo.shr(1) + ((a.lo & b.lo) & 1) }).shr(63) }
  )
}

main := fn() -> u64 {
  a := U128(lo = 18446744073709551615, hi = 0)
  b := U128(lo = 1, hi = 0)
  r := a + b

  c := U128(lo = 5, hi = 6)
  d := U128(lo = 10, hi = 20)
  s := c + d

  return r.lo + r.hi + s.lo + s.hi
}
