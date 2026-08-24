## Inside `unchecked`, the over-width shift guard is dropped, but the typed operation's result is still
## narrowed to the operand width. On x86 `shlq` leaves `1 << 9 == 512`, narrowed to `u8` => 0.
main := fn() -> u64 {
  x : u8 = 1
  y : u8 = unchecked { shl(x, 9) }
  if y == 0 { return 42 }
  return 1
}
