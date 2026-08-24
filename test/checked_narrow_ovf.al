## Checked-mode NARROW-WIDTH overflow trap (I11 / CG-8): `200u8 + 100u8` = 300 > 255 does not fit u8,
## so the checked guard TRAPS (x86 shr-check + ud2 → 132) BEFORE the value-model wrap. Companion
## narrow_wrap_builtin uses `unchecked` to select the wrap (44) instead. x86-only (narrow arith is
## x86-only today — the native backends model neither the wrap nor this trap yet).
main := fn() -> u64 {
  a : u8 = 200
  b : u8 = 100
  x := a + b
  return x
}
