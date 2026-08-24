## Narrow-width bitwise NOT `~` masks to the operand width (§4 value model). `~x` desugars to
## `x ^ (-1)` with a 64-bit all-ones constant; for a `u8` operand the result must be masked to 8 bits
## (`~213u8` = 42, not 0xFF…FF2A). The exit code only shows the low byte, so compare the FULL value:
## masked → `u64(y) == 42` → 42; un-masked (the bug) → a huge value → 7. x86-only (narrow arith x86-only).
main := fn() -> u64 {
  x : u8 = 213
  y := ~x
  if u64(y) == 42 { return 42 } else { return 7 }
}
