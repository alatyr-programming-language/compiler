## e2e: the bit shift/rotate OPERATION-FUNCTIONS (OP-6) — `shl`/`shr`/`rotl`/`rotr`, named call/UFCS ops
## (no `<<`/`>>` glyph). `shl` fills low bits with 0; `shr` selects the intrinsic by the value's signedness
## (a `uN`/`bitsN` → logical zero-fill, an `iN` → arithmetic sign-fill); rotations are total (count mod N).
## An over-width shift (count >= width) traps (I11) — not exercised here (a run test can't assert a trap).
## Exercises: UFCS `a.shl(2)`=40, logical `shr(168,2)`=42, arithmetic `shr(-40,1)`=-20, `rotl(1,4)`=16,
## `rotr(16,4)`=1. Answer 40 + 2 = 42 with the rest checked by guards.
main := fn() -> u64 {
  a : u64 = 10
  b : u64 = 168
  s : i64 = 0 - 40
  x := a.shl(2)          ## 40 (UFCS spelling)
  y := shr(b, 2)         ## 42 (logical right)
  z : i64 = shr(s, 1)    ## -20 (arithmetic right)
  r := rotl(u64(1), 4)   ## 16
  w := rotr(r, 4)        ## 1
  if y != 42 { return 1 }
  if z != (0 - 20) { return 2 }
  if r != 16 { return 3 }
  if w != 1 { return 4 }
  return x + 2           ## 42
}
