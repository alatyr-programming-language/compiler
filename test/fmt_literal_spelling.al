## `fmt` must preserve the author's integer spelling, not only its value. The four forms below
## deliberately spell the same value differently; the e2e fmt lock checks each token survives. The
## high-bit tail also proves a source literal with the `-1` bit pattern is not mistaken for Num(-1)'s
## internal no-tail sentinel.
max_word := fn() -> u64 { 0xffffffffffffffff }
main := fn() -> u64 {
  hex := 0x2A
  oct := 0o52
  bin := 0b101010
  separated := 1_000
  if hex != 42 { return 0 }
  if oct != 42 { return 0 }
  if bin != 42 { return 0 }
  if separated != 1000 { return 0 }
  if max_word() != 18446744073709551615 { return 0 }
  return 42
}
