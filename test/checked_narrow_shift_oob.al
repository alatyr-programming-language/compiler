## Checked-mode over-width shift trap for a NARROW operand (I11 / OP-6): for `u8`, a shift count
## `n >= 8` traps. The x86 lower used to guard only against `n >= 64`, so `shl(u8(1), 8)` ran.
main := fn() -> u64 {
  x : u8 = 1
  return shl(x, 8)
}
