## §8 @packed / @offset with a NON-scalar field that is a FIXED ARRAY, and a scalar field read PAST it
## (spec Types §8). A `[u64; 3]` array field keeps its natural 8-byte-per-element word layout; placed at
## byte 8 (@offset(8), 8-aligned) it occupies bytes 8..32, so the following scalar `val` lands at the
## running cursor byte 32 — proving the array advanced the cursor by its FULL 24 bytes. The observers
## `d0`/`d1`/`d2` overlay the three element words with native u64 reads, proving the array was stored.
##   tag : u8       @0
##   data: [u64;3]  @8   -> [8, 16, 24]   (24 bytes)
##   val : u32      @32
##   d0 @8  d1 @16  d2 @24  (overlays of data[0..3])
## Constructed positionally: tag, data, val; d0/d1/d2 are unwritten observers. Returns 42.
Blk := @packed struct {
  tag : u8,
  @offset(8) data : [u64; 3],
  val : u32,
  @offset(8) d0 : u64,
  @offset(16) d1 : u64,
  @offset(24) d2 : u64
}

main := fn() -> u64 {
  b := Blk(tag = 5, data = [11, 13, 15], val = 100)
  if size(Blk) != 36 { return 1 }          ## tag@0, data@8..32 (24 bytes), val@32..36 -> 36
  if u64(b.tag) != 5 { return 2 }
  if u64(b.d0) != 11 { return 3 }           ## data[0] at byte 8
  if u64(b.d1) != 13 { return 4 }           ## data[1] at byte 16
  if u64(b.d2) != 15 { return 5 }           ## data[2] at byte 24
  if u64(b.val) != 100 { return 6 }         ## the scalar PAST the array, at byte 32
  return 42
}
