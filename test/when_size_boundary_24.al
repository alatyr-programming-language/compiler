## CLAYOUT S2 boundary probe: `when size(T) > 24` must use the same byte-size
## ladder as the direct `size(T)` fold for a standard byte-layout struct, a mixed
## tuple, and an ordinary word-layout struct.
Byte25 := struct { data : [u8;25] }
Word32 := struct { a : u64, b : u64, c : u64, d : u64 }

pick := fn(T : type, x : u64) -> u64 when size(T) > 24 { x }

main := fn() -> u64 {
  sb := size(Byte25)
  st := size((u64, u8, u64, u8))
  sw := size(Word32)
  if sb == 25 and st == 32 and sw == 32 {
    return pick(Byte25, 10) + pick((u64, u8, u64, u8), 14) + pick(Word32, 18)
  }
  return 1
}
