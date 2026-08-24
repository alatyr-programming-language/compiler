## e2e — the bound is on the VALUE, not the spelling: all four bases decode through the same
## `parser::dec_val`, so `0x1FF` is as out of range for `u8` as `511` is. Located line 4.
main := fn() -> i64 {
  x : u8 = 0x1FF
  return i64(x)
}
