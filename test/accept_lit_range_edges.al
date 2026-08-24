## e2e — the ACCEPT sibling of the `reject_lit_range_*` family: every BOUNDARY value that IS
## representable must still pass, and must still carry its real value at run time (Types §9.1). One
## reject and one accept per width, so the check cannot pass by rejecting the whole family.
##
## `u64`/`usize` hold every 64-bit pattern, so no literal is ever out of range for them — including
## one at or above 2^63, whose `Expr::Num` payload comes back NEGATIVE.
Gu : u8 = 255
Gi : i8 = 127

f8 := fn(v : u8) -> u64 {
  return u64(v)
}

g8 := fn() -> u8 {
  return 255
}

main := fn() -> u64 {
  a : u8 = 255
  b : i8 = 127
  c : u16 = 65535
  d : i16 = 32767
  e : u32 = 4294967295
  h : i32 = 2147483647
  i : i64 = 9223372036854775807
  j : u64 = 18446744073709551615
  k : usize = 18446744073709551615
  if u64(a) != 255 { return 1 }
  if i64(b) != 127 { return 2 }
  if u64(c) != 65535 { return 3 }
  if i64(d) != 32767 { return 4 }
  if u64(e) != 4294967295 { return 5 }
  if i64(h) != 2147483647 { return 6 }
  if i != 9223372036854775807 { return 7 }
  if j != 18446744073709551615 { return 8 }
  if k != 18446744073709551615 { return 9 }
  if u64(Gu) != 255 { return 10 }
  if i64(Gi) != 127 { return 11 }
  if f8(255) != 255 { return 12 }
  if u64(g8()) != 255 { return 13 }
  return 42
}
