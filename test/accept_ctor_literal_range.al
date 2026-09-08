## Types §9.1 / §4.2 (#564) — the three CONTROLS of the constructor-literal refusal, with a
## four-backend witness that none of them moved:
##   1. CG-7 — inside an `unchecked` scope a narrowing conversion TRUNCATES, and the §9.1 refusal
##      must not reach it: `unchecked u8(300)` is specified behaviour, not the defect.
##   2. every REPRESENTABLE literal still converts, including the exact boundaries 255 / 65535 /
##      4294967295 / 127 / 32767 and the negative bound -128.
##   3. a NON-LITERAL operand is §4.2's run-time narrowing, whose value is not a compile-time fact;
##      it keeps truncating and is deliberately untouched by this unit.
## The signed rows assert the VALUE, not an exit code: no cross-backend fixture asserted a negative
## number before (#444), and the signed half of §9.1's bound is exactly about them.
main := fn() -> u64 {
  a := unchecked u8(300)
  if u64(a) != 44 { return 11 }
  b := unchecked u8(1000)
  if u64(b) != 232 { return 12 }
  if u64(u8(255)) != 255 { return 13 }
  if u64(u8(0)) != 0 { return 14 }
  if u64(u16(65535)) != 65535 { return 15 }
  if u64(u32(4294967295)) != 4294967295 { return 16 }
  if i64(i8(127)) != 127 { return 17 }
  if i64(i16(32767)) != 32767 { return 18 }
  lo := i8(0 - 128)
  if i64(lo) != 0 - 128 { return 19 }
  neg := i8(0 - 1)
  if i64(neg) != 0 - 1 { return 20 }
  v : u64 = 810
  if u64(u8(v)) != 42 { return 21 }
  s : u64 = 200
  if i64(i8(s)) != 0 - 56 { return 22 }
  42
}
