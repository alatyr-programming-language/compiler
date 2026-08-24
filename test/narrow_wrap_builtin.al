## §4 value model: `unchecked` narrow-width arithmetic WRAPS at the type width. `200u8 + 100u8` is
## `44u8` (300 & 0xFF), not the 64-bit 300 — so `x < 50` is true. Under CHECKED (the default) this same
## `+` now TRAPS (300 > 255, I11 / CG-8) — the `unchecked` scope selects the value-model wrap instead.
## The lower truncates the result of a narrow-typed `+`/`-`/`*` to its width (and, when checked, first
## traps if it did not fit). (A ROUTED width operator — see width_wrap_arith — already did.)
main := fn() -> u64 {
  a : u8 = 200
  b : u8 = 100
  x := unchecked { a + b }
  if x < 50 { return 42 }
  return 1
}
