## e2e — #1758 (IR-33): a struct with a direct byte-array field is laid out in the BYTE tier
## (`lower_layout::layout_kind`; Types §6.1 declaration order and natural alignment, Types §6.4 a byte
## element at stride 1), and a `@packed` one byte by byte (Types §8). The shared IR builds such a struct
## as a local: its literal, element reads and writes of the byte field, a scalar field placed after it,
## a word-granular struct child (whose word and byte layouts coincide), and a whole copy.
## 1 + 30 + 300 - 300 = 31; 4 + 6 - 1 = 9; 8 + 9 + 70000 - 70000 = 17; 31 + 9 + 17 - 15 = 42.
## expect: run 42
S := struct { data : [u8; 4], tail : u16 }
W := struct { x : u64, y : u64 }
O := struct { tag : u8, raw : [u8; 3], inner : W }
P := @packed struct { tag : u8, data : [u8; 3], tail : u32 }

byte_field := fn() -> u64 {
  mut s := S(data = [1, 2, 3, 4], tail = 300)
  s.data[2] = 30
  u64(s.data[0]) + u64(s.data[2]) + u64(s.tail) - 300
}

word_child := fn() -> u64 {
  o := O(tag = 1, raw = [2, 3, 4], inner = W(x = 5, y = 6))
  c := o
  u64(c.raw[2]) + c.inner.y - u64(c.tag)
}

packed_field := fn() -> u64 {
  p := P(tag = 9, data = [7, 8, 1], tail = 70000)
  u64(p.data[1]) + u64(p.tag) + u64(p.tail) - 70000
}

main := fn() -> u64 {
  byte_field() + word_child() + packed_field() - 15
}
