## A raw str view may be built only through the explicitly unchecked str_at escape hatch.
## The view exposes one byte, while the backing array places three sentinel bytes after it.
## CharIter must trap before reading those bytes past the view's declared length.
main := fn() -> u64 {
  raw : [u8; 4] = [0xF0, 0x80, 0x80, 0x80]
  if base::str::byte_len("x") != 1 { return 40 }
  mut it : CharIter = CharIter(ptr = ptr(raw[0]), len = 1, pos = 0)
  c := unwrap(char, next(it))
  if u32(c) == 0 { return 41 }
  42
}
