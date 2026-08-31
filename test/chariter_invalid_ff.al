## A raw str view may contain bytes that are not a valid UTF-8 lead sequence.
## An in-bounds 0xFF lead must fail loudly instead of producing a char above Unicode's range.
main := fn() -> u64 {
  raw : [u8; 4] = [0xFF, 0x80, 0x80, 0x80]
  if base::str::byte_len("x") != 1 { return 40 }
  mut it : CharIter = CharIter(ptr = ptr(raw[0]), len = 4, pos = 0)
  c := unwrap(char, next(it))
  if u32(c) == 0 { return 41 }
  42
}
