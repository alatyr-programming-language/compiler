## §8 @packed / @offset with a NON-scalar field that is itself a STRUCT, and a scalar field read PAST it
## (spec Types §8). A nested (word-model) struct keeps its natural 8-byte alignment inside the packed
## struct; here `inner` (an `Inner{x,y}`, 16 bytes) sits at byte 8 (@offset(8), 8-aligned), so the
## following scalar `val` lands at the running cursor byte 24 — proving the nested struct advanced the
## cursor by its FULL 16 bytes (not a mis-sized 8). The observers `ix`/`iy` overlay `inner`'s two words
## with native u64 reads, proving the nested struct's fields were actually stored.
##   tag  : u8  @0
##   inner: Inner @8   -> x @8, y @16   (16 bytes)
##   val  : u32 @24
##   ix   : u64 @8  (overlay of inner.x)   iy : u64 @16 (overlay of inner.y)
## Constructed positionally: tag, inner, val; ix/iy are unwritten observers. Returns 42.
Inner := struct { x : u64, y : u64 }

Outer := @packed struct {
  tag : u8,
  @offset(8) inner : Inner,
  val : u32,
  @offset(8) ix : u64,
  @offset(16) iy : u64
}

main := fn() -> u64 {
  o := Outer(tag = 5, inner = Inner(x = 20, y = 22), val = 100)
  if size(Outer) != 28 { return 1 }        ## tag@0, inner@8..24 (16 bytes), val@24..28 -> 28
  if u64(o.tag) != 5 { return 2 }
  if u64(o.ix) != 20 { return 3 }           ## inner.x stored at byte 8
  if u64(o.iy) != 22 { return 4 }           ## inner.y stored at byte 16
  if u64(o.val) != 100 { return 5 }         ## the scalar PAST the nested struct, at byte 24
  return 42
}
