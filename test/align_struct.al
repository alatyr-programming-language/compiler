## §8 @align(N) — raise a field's alignment ABOVE natural (spec Types §8), extending the @packed
## byte-precise layout. In a @packed struct fields pack with no padding at a running byte cursor;
## a field carrying `@align(N)` is placed only after the cursor is rounded UP to a multiple of N, and
## the struct's total size is rounded up to the struct's alignment (the max field alignment). Here:
##   a : u8        @0  (1 byte)                 cursor -> 1
##   @align(4) b   @4  (round 1 up to 4; 4 bytes) cursor -> 8
##   c : u8        @8  (1 byte)                 cursor -> 9
## struct alignment = max(1, 4) = 4, so size rounds 9 up to 12 (a plain @packed layout would be 6).
## A wrong or ignored @align would place b at byte 1 and size the struct 6/8/9 — the size == 12 check
## proves BOTH the cursor rounding (b @ 4) and the trailing size rounding fired; the field reads prove
## the store/load byte offsets agree (b = 100000 needs a full 4-byte slot). Returns 42.
Al := @packed struct { a : u8, @align(4) b : u32, c : u8 }

main := fn() -> u64 {
  p := Al(a = 10, b = 100000, c = 7)
  ## observable alignment: size is 12 (natural-aligned packed), not 6 (unaligned packed).
  if size(Al) != 12 { return 1 }
  ## sized reads at the aligned offsets: each field's full value survives.
  if u64(p.a) != 10 { return 2 }
  if u64(p.b) != 100000 { return 3 }
  if u64(p.c) != 7 { return 4 }
  return 42
}
