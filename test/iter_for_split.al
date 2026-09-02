## e2e — Stdlib appendix §2.4, the SECOND iterator in the base library: `SplitIter` also provides
## `next(in out self) -> Opt`, so `for part in <SplitIter>` must yield the SUBSTRINGS between the
## separator bytes, not walk the backing view's byte length.
##
## Failure-first on parent f14b3d9 (x86_64, default build path): `"a,bb,ccc"` is 3 pieces in 8 bytes,
## and the loop ran 8 times — `103` here versus the parent's `108` on the same counting shape. Kept
## separate from `iter_for_chars` so a regression names the type it broke; `SplitIter`'s `{ptr, len}`
## prefix is what made the counted form look applicable, and its two extra fields (`sep`, `pos`,
## `done`) are exactly why the count was wrong in a different way than `CharIter`'s.
##
## Piece CONTENTS are not asserted: `str` equality on a yielded piece is a separate surface, and
## `split`'s own piece boundaries are proven elsewhere. This fixture proves the loop FORM — the
## iteration COUNT is the measurement #402 recorded — with each rejection code distinct and >= 100.

main := fn() -> u64 {
  s := "a,bb,ccc"
  mut it := base::str::SplitIter(ptr = s.ptr, len = s.len, sep = 44, pos = 0, done = false)
  if it.len != 8 { return 101 }

  mut n : u64 = 0
  for p in it {
    n = n + 1
    if n > 8 { return 102 }
  }
  if n != 3 { return 100 + n }

  ## no separator at all is ONE piece, not `len` pieces
  t := "abc"
  mut u := base::str::SplitIter(ptr = t.ptr, len = t.len, sep = 44, pos = 0, done = false)
  mut m : u64 = 0
  for p in u {
    m = m + 1
    if m > 4 { return 110 }
  }
  if m != 1 { return 111 }

  42
}
