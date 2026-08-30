## Issue #261 — the parent compiler returns 101 because byte indexing through a Slice(u8)
## struct field loses the backing base at the first checked index; the fixed program returns 42.
##
## The byte view is checked at every index of a non-uniform array. The u16/u32/u64 view
## fields are width controls; the length and a local Slice(u8) are independent controls.
Views := struct {
  bytes : Slice(u8),
  words16 : Slice(u16),
  words32 : Slice(u32),
  words64 : Slice(u64)
}

main := fn() -> u64 {
  bytes : [u8; 4] = [3, 11, 29, 47]
  words16 : [u16; 4] = [101, 203, 307, 401]
  words32 : [u32; 4] = [1001, 2003, 3007, 4009]
  words64 : [u64; 4] = [10001, 20003, 30007, 40009]
  views := Views(
    bytes = bytes[0..4],
    words16 = words16[0..4],
    words32 = words32[0..4],
    words64 = words64[0..4]
  )

  if u64(views.bytes[0]) != 3 { return 101 }
  if u64(views.bytes[1]) != 11 { return 102 }
  if u64(views.bytes[2]) != 29 { return 103 }
  if u64(views.bytes[3]) != 47 { return 104 }
  if u64(views.bytes.len) != 4 { return 105 }

  if u64(views.words16[2]) != 307 { return 106 }
  if u64(views.words32[1]) != 2003 { return 107 }
  if views.words64[3] != 40009 { return 108 }

  local := bytes[0..4]
  if u64(local[3]) != 47 { return 109 }
  return 42
}
