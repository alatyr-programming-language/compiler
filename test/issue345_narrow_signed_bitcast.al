## Issue #345 / Types §§3.4, 4.4 — equal-width bitcasts preserve the narrow bit pattern, not the
## source's already-extended machine word. The signed source cases are the failure-first witnesses:
## before the fix, i8/i16/i32 MIN values retain all-one high bits and compare as the wrong unsigned
## result. The reverse direction proves a signed destination re-extends its low bit pattern.
## A narrow bitcast as the CONDITION ITSELF, inside a TAIL-VALUE fn. `is_scalar_leaf_shape` refuses a
## `return`-terminated body, so `main` alone can never make the compact IR walk a condition: measured
## with a temporary `panic` in `src/lower/ir.al`'s `ir_check_cond` arm, no fixture reached it and this
## shape does. The arm refuses narrow bitcasts so the text emitter owns the destination normalization;
## `ir_lower_cond`'s matching arm stays a defence-in-depth trap behind that refusal.
narrow_cond := fn(b : bool) -> u64 {
  mut r : u64 = 0
  if bitcast(bool, b) { r = 42 }
  r
}
main := fn() -> u64 {
  neg8 : i8 = 0 - 128
  ## The DIRECT comparison is the issue #345 reproduction and the strong form: an INFERRED local
  ## bound from the bitcast is typed by the TARGET, so `!= 128` compares the destination word
  ## itself. The `u64(...)` spelling below is weaker — it would keep passing if a `u64()` widening
  ## from `u8` ever stopped being a code-noop and masked the stale sign bits — so both spellings are
  ## asserted here and must agree, exactly as `alatyr run` and build-then-execute must agree.
  direct_bits := bitcast(u8, neg8)
  if direct_bits != 128 { return 1 }
  u8_bits : u8 = bitcast(u8, neg8)
  if u64(u8_bits) != 128 { return 15 }
  i8_bits : i8 = bitcast(i8, u8(128))
  if i8_bits != 0 - 128 { return 2 }
  u8_same : u8 = bitcast(u8, u8(255))
  if u64(u8_same) != 255 { return 3 }
  bits8_value : u8 = bitcast(bits8, neg8)
  if u64(bits8_value) != 128 { return 4 }

  neg16 : i16 = 0 - 32768
  u16_bits : u16 = bitcast(u16, neg16)
  if u64(u16_bits) != 32768 { return 5 }
  i16_bits : i16 = bitcast(i16, u16(32768))
  if i16_bits != 0 - 32768 { return 6 }
  u16_same : u16 = bitcast(u16, u16(65535))
  if u64(u16_same) != 65535 { return 7 }
  bits16_value : u16 = bitcast(bits16, neg16)
  if u64(bits16_value) != 32768 { return 8 }

  neg32 : i32 = 0 - 2147483648
  u32_bits : u32 = bitcast(u32, neg32)
  if u64(u32_bits) != 2147483648 { return 9 }
  i32_bits : i32 = bitcast(i32, u32(2147483648))
  if i32_bits != 0 - 2147483648 { return 10 }
  u32_same : u32 = bitcast(u32, u32(4294967295))
  if u64(u32_same) != 4294967295 { return 11 }
  bits32_value : u32 = bitcast(bits32, neg32)
  if u64(bits32_value) != 2147483648 { return 12 }

  unchecked_u8 : u8 = unchecked bitcast(u8, neg8)
  if u64(unchecked_u8) != 128 { return 13 }
  unchecked_i8 : i8 = unchecked bitcast(i8, u8(128))
  if unchecked_i8 != 0 - 128 { return 14 }

  ## A narrow bitcast in CONDITION position rather than an initializer. Every assertion above sits on
  ## the right-hand side of a local binding, so the compact-IR CONDITION arms (`ir_check_cond` /
  ## `ir_lower_cond` in `src/lower/ir.al`) were never reached by any fixture: their refusal of this
  ## shape was untested, and an IR path that silently erased the target here would have gone unseen.
  ## The first two lines put the cast inside the condition EXPRESSION; `narrow_cond` below makes the
  ## cast BE the condition inside a TAIL-VALUE fn, which is the only shape those arms actually see.
  if bitcast(u8, neg8) != 128 { return 16 }
  if unchecked bitcast(i8, u8(128)) != 0 - 128 { return 17 }
  if narrow_cond(true) != 42 { return 18 }
  if narrow_cond(false) != 0 { return 19 }
  return 42
}
