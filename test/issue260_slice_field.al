## Issue #260: narrow scalar fields in a Slice(struct) must use the struct's
## byte layout after the Slice element address has been computed.
Pair8 := struct { left : u8, right : u8 }
Pair16 := struct { head : u16, tail : u16 }
Wide := struct { first : u64, second : u64 }

read8 := fn(view : Slice(Pair8)) -> u64 {
  u64(view[1].left) + u64(view[1].right)
}
read16 := fn(view : Slice(Pair16)) -> u64 {
  u64(view[1].head) + u64(view[1].tail)
}
read_wide := fn(view : Slice(Wide)) -> u64 {
  view[1].first + view[1].second
}

main := fn() -> u64 {
  bytes : [Pair8; 2] = [Pair8(left = 13, right = 17), Pair8(left = 19, right = 23)]
  byte_view := bytes[0..2]
  if u64(byte_view[1].left) != 19 { return 90 }
  if u64(byte_view[1].right) != 23 { return 91 }
  if read8(byte_view) != 42 { return 92 }
  if u64(bytes[1].left) != 19 { return 93 }
  if u64(bytes[1].right) != 23 { return 94 }

  halfs : [Pair16; 2] = [Pair16(head = 101, tail = 103), Pair16(head = 107, tail = 109)]
  half_view := halfs[0..2]
  if u64(half_view[1].head) != 107 { return 95 }
  if u64(half_view[1].tail) != 109 { return 96 }
  if read16(half_view) != 216 { return 97 }

  wide : [Wide; 2] = [Wide(first = 1, second = 2), Wide(first = 4, second = 6)]
  wide_view := wide[0..2]
  if read_wide(wide_view) != 10 { return 98 }
  return 42
}
