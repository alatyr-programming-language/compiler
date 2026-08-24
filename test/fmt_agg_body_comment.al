## fmt fixture — an aggregate body carrying `##` COMMENTS (Types §8). The verbatim-body path that
## preserves member attributes has to find the body's closing brace, and it used the shared
## `skip_balanced_group`, which treats `'` as a char-literal opener. An APOSTROPHE inside a body
## comment therefore swallowed the rest of the body, the scan returned 0, and fmt fell back to the
## canonical rebuild — dropping the very `@offset` attributes the verbatim path exists to keep
## (`endian_offset_struct` ran 42 -> 2). A member list holds no char literals, so the body scanner is
## now comment-aware and treats `'` as an ordinary byte. Returns 42.
Ov := @packed struct {
  @offset(0) w : u32,     ## the written field — it's at byte 0
  @offset(0) b0 : u8,     ## an alias reading w's lowest byte
  @offset(3) b3 : u8      ## an alias reading w's highest byte
}

main := fn() -> u64 {
  x := Ov(w = 16777226)
  if u64(x.b0) != 10 { return 1 }
  if u64(x.b3) != 1 { return 2 }
  if size(Ov) != 4 { return 3 }
  return 42
}
