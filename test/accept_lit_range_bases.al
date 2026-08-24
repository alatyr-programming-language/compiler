## e2e — the ACCEPT sibling for the BASE half of `reject_lit_range_hex.al`: all four bases decode to
## the same value, so the IN-RANGE spelling in every base must still pass and still carry its value
## (Grammar §2.4 / Types §9.1). `255` is the `u8` boundary in each.
main := fn() -> u64 {
  a : u8 = 0xFF
  b : u8 = 0b11111111
  c : u8 = 0o377
  d : u8 = 255
  e : u8 = 0xF_F
  if u64(a) != 255 { return 1 }
  if u64(b) != 255 { return 2 }
  if u64(c) != 255 { return 3 }
  if u64(d) != 255 { return 4 }
  if u64(e) != 255 { return 5 }
  return 42
}
