## §8 SUB-8 @packed local COPY (spec Types §8) — a `@packed` struct whose total size is NOT a multiple
## of 8 (`P` = {u8 a, u32 b} = 5 bytes), copied by value to another local (`dst := src`), with a u64
## SENTINEL neighbour. A frame LOCAL of a packed struct is reserved `ceil(bytes/8)` WORDS (1 word for
## 5 bytes — see `struct_words`'s `@packed` floor in lower_layout), so a whole-WORD copy stays inside
## the destination's own word slot and never writes past the struct into the neighbour: the copy is
## SAFE for a word-padded local. (The genuine sub-8 over-write hazard lives only inside a byte-strided
## array-of-packed, which is rejected fail-loud — see test/packed_array.al.) This pins the working case:
## the copied fields round-trip (7 / 12345) AND the sentinel is intact → 42.
P := @packed struct { a : u8, b : u32 }

main := fn() -> u64 {
  if size(P) != 5 { return 90 }
  src : P = P(a = 7, b = 12345)
  sentinel : u64 = 6148914691236517121   ## 0x5555555555550001, a distinctive neighbour pattern
  dst := src
  if u64(dst.a) != 7 { return 10 }
  if u64(dst.b) != 12345 { return 11 }
  if sentinel != 6148914691236517121 { return 20 }
  return 42
}
