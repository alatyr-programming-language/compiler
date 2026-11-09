## Issue #261 — the parent compiler returns 101 because byte indexing through a Slice(u8)
## struct field loses the backing base at the first checked index; the fixed program returns 42.
##
## The byte view is checked at every index of a non-uniform array. The u64 view field is a width
## control; the length and a local Slice(u8) are independent controls.
##
## The u16/u32 view fields that stood here passed only because the field index stepped a word over a
## word-layout `[u16; N]` / `[u32; N]` (#1514): Types §6.4 makes a `Slice(T)` step `T`'s own size.
## x86_64 now refuses that range slice until those arrays are packed (#1559,
## test/issue1514_word_array_range_slice.al); the field consumer over a packed source is #1561.
Views := struct {
  bytes : Slice(u8),
  words64 : Slice(u64)
}

main := fn() -> u64 {
  bytes : [u8; 4] = [3, 11, 29, 47]
  words64 : [u64; 4] = [10001, 20003, 30007, 40009]
  views := Views(
    bytes = bytes[0..4],
    words64 = words64[0..4]
  )

  if u64(views.bytes[0]) != 3 { return 101 }
  if u64(views.bytes[1]) != 11 { return 102 }
  if u64(views.bytes[2]) != 29 { return 103 }
  if u64(views.bytes[3]) != 47 { return 104 }
  if u64(views.bytes.len) != 4 { return 105 }

  if views.words64[3] != 40009 { return 108 }

  local := bytes[0..4]
  if u64(local[3]) != 47 { return 109 }
  return 42
}
## expect(x86_64): run 42
