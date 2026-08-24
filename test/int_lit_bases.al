## e2e — NON-DECIMAL integer literals (Grammar §2.4 `hex-int` / `oct-int` / `bin-int`, SYN-3).
## Before this the lexer stopped the number token at the first non-decimal byte, so `0b1000` lexed
## as `0` + the identifier `b1000` and the literal's VALUE became plain `0` — a SILENT WRONG VALUE,
## with no diagnostic. Same for `0o777`. Returns 42 only when every base decodes to its true value.
main := fn() -> u64 {
  if 0b1000 != 8 { return 1 }
  if 0b0 != 0 { return 2 }
  if 0b11111111 != 255 { return 3 }
  if 0o777 != 511 { return 4 }
  if 0o0 != 0 { return 5 }
  if 0o17 != 15 { return 6 }
  if 0xFF != 255 { return 7 }
  if 0xff != 255 { return 8 }
  if 0xdeadbeef != 3735928559 { return 9 }
  ## a base prefix COMBINED with `_` separators (both grammar productions admit `{ digit | "_" }`)
  if 0b1010_1010 != 170 { return 10 }
  if 0o7_7_7 != 511 { return 11 }
  if 0xF_F != 255 { return 12 }
  ## the bases agree with each other, not merely with a constant folded the same wrong way
  if 0b100000 != 0o40 { return 13 }
  if 0o40 != 0x20 { return 14 }
  if 0x20 != 32 { return 15 }
  return 42
}
