## e2e — the 64-bit BOUNDARY of an integer literal in every base (Types §9.1: a literal's
## representability is checked at compile time; §11 — out-of-range is a compile error, never a
## silent wrap). The largest in-range value must survive DECODING intact: `18446744073709551615`,
## `0xFFFFFFFFFFFFFFFF`, `0o1777777777777777777777` and 64 binary ones are the SAME value, and
## 2^63 is exactly one more than i64's maximum. An exit code cannot carry these (it truncates
## mod 256), so every comparison is made INSIDE the program and only the verdict is returned.
main := fn() -> u64 {
  umax : u64 = 18446744073709551615
  if umax != 0xFFFFFFFFFFFFFFFF { return 1 }
  if umax != 0o1777777777777777777777 { return 2 }
  if umax != 0b1111111111111111111111111111111111111111111111111111111111111111 { return 3 }
  if umax != 18_446_744_073_709_551_615 { return 4 }
  ## 2^63 — one past i64's maximum, and the exact bit pattern 0x8000…0
  hb : u64 = 9223372036854775808
  if hb != 0x8000000000000000 { return 5 }
  if hb != 9_223_372_036_854_775_808 { return 6 }
  if hb != 0b1000000000000000000000000000000000000000000000000000000000000000 { return 7 }
  imax : u64 = 9223372036854775807
  if hb - imax != 1 { return 8 }
  if imax != 0x7FFFFFFFFFFFFFFF { return 9 }
  ## the halves really are the halves — a truncated decode could not satisfy this
  if umax - hb != imax { return 10 }
  return 42
}
