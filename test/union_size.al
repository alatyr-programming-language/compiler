## Raw union (spec Types §6.3) — SIZE/ALIGN are the MAXIMA over members, with NO discriminant word.
## Pair is 2 words. `union { a(u64), p(Pair) }` sizes to the WIDEST member (2 words = 16 bytes), not
## `1 + sum`. Contrast the tagged `enum { a(u64), b(u64) }`, which is `1 (tag) + 1 (payload)` = 16 —
## twice the untagged `union { a(u64), b(u64) }` (8): the missing 8 bytes ARE the absent tag word.
Pair := struct { x : u64, y : u64 }
Wide := union { a(u64), p(Pair) }
Scalars := union { a(u64), b(u64) }
Tagged := enum { a(u64), b(u64) }
main := fn() -> u64 {
  if size(Scalars) == 8 and size(Wide) == 16 and align(Wide) == 8 and size(Tagged) == 16 { return 42 }
  return 0
}
