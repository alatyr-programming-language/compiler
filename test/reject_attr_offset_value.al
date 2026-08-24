## e2e (reject) — the VALUE-position twin of `reject_attr_offset_prefix.al`. `@offset(N)` gives a
## FIELD an explicit byte offset (Types §8); after the `:=` it prefixes a TYPE, which has no offset to
## give. Silently dropped before this (the struct laid out unchanged); now a located reject, so both
## spellings of the same mistake answer the same way.
S := @offset(8) struct { a : u8, b : u8 }
main := fn() -> u64 {
  s := S(a = 1, b = 2)
  return u64(s.a) + u64(s.b)
}
