## §8 @packed / @offset with a NON-scalar (str) field, and a scalar field read PAST it, by value (spec
## Types §8). A `str` is a 2-word {ptr, len} value (16 bytes). In a @packed struct an aggregate/str field
## keeps its natural 8-byte alignment; here `name` is placed at byte 8 (@offset(8), 8-aligned), so it
## occupies bytes 8..24 and the following scalar `val` lands at the running cursor byte 24 — NOT byte 16
## (which is where a str mis-sized as one 8-byte word would put it). The observer `namelen` overlays the
## str's LEN word at byte 16 with a native u64 read, proving the str's second word was actually stored.
##   tag    : u8  @0
##   name   : str @8   -> ptr @8, len @16   (16 bytes)
##   val    : u32 @24  (cursor after the 16-byte str)
##   namelen: u64 @16  (overlay of name.len)
## Values are constructed in declaration order (positional): tag, name, val; namelen is an unwritten
## observer. A str mis-sized as 8 bytes would place val at byte 16 (aliasing name.len) and read garbage;
## a dropped str store would leave namelen unset. Returns 42.
Rec := @packed struct {
  tag : u8,
  @offset(8) name : str,
  val : u32,
  @offset(16) namelen : u64
}

main := fn() -> u64 {
  r := Rec(tag = 5, name = "hello", val = 100)
  if size(Rec) != 28 { return 1 }         ## tag@0..1, name@8..24, val@24..28 -> 28 (str sized 16, not 8)
  if u64(r.tag) != 5 { return 2 }
  if u64(r.namelen) != 5 { return 3 }      ## "hello".len == 5, read at byte 16 -> the str's len word was stored
  if u64(r.val) != 100 { return 4 }        ## the scalar PAST the str reads its own value at byte 24
  return 42
}
