## Types §9.1 / Declarations §3.4 — no-context integer literals use the
## native signed default. The positive i64 boundary is valid in decimal and
## hexadecimal, for both a module-level and a local inferred binding.
G := 9223372036854775807

main := fn() -> u64 {
  a := 9223372036854775807
  b := 0x7FFFFFFFFFFFFFFF
  if a != 9223372036854775807 { return 1 }
  if b != 9223372036854775807 { return 2 }
  if G != 9223372036854775807 { return 3 }
  return 42
}
