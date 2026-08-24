## §8 DIRECT aggregate-field READ from a @packed struct (spec Types §8) — the read counterpart of the
## aggregate WRITE side. A nested-struct field's scalar sub-field (`r.inner.x`) and a str field's `.len`
## (`r.name.len`) are read through the packed byte layout: the aggregate was stored at an 8-aligned
## byte→slot position via the word-model emitters, so its sub-fields are read at their word-model slots
## within it. Formerly the packed read path handled only a scalar `Var`-based `r.f`; `r.inner.x` /
## `r.name.len` fell through to the word-offset paths (incompatible with the packed byte layout).
##   tag  : u8    @0
##   inner: Inner @8   -> x @8, y @16   (16 bytes)
##   name : str   @24  -> ptr @24, len @32   (16 bytes)
##   val  : u32   @40
## All fields constructed positionally. Reads r.inner.x / r.inner.y / r.name.len / r.val directly.
## Returns tag + inner.x + inner.y + name.len = 5 + 15 + 20 + 2 = 42.
Inner := struct { x : u64, y : u64 }

Rec := @packed struct {
  tag : u8,
  @offset(8) inner : Inner,
  @offset(24) name : str,
  @offset(40) val : u32
}

main := fn() -> u64 {
  r := Rec(tag = 5, inner = Inner(x = 15, y = 20), name = "hi", val = 100)
  if u64(r.tag) != 5 { return 1 }
  if r.inner.x != 15 { return 2 }          ## DIRECT nested-struct sub-field read (byte 8)
  if r.inner.y != 20 { return 3 }          ## DIRECT nested-struct sub-field read (byte 16)
  if r.name.len != 2 { return 4 }          ## DIRECT str .len read ("hi".len == 2, byte 32)
  if u64(r.val) != 100 { return 5 }        ## scalar PAST both aggregates (byte 40)
  return u64(r.tag) + r.inner.x + r.inner.y + r.name.len
}
