## e2e — NON-NATIVE integer width conversions on every backend (§4). Types §4.2 (narrow row): a
## narrowing `T(v)` is checked by default — it traps when the value does not fit — and inside an
## `unchecked` scope it truncates (CG-7): `uN(x)` keeps the low N bits zero-extended, `iN(x)` sign-
## extends them.
##
## This row asserted 42 for three CHECKED out-of-range narrowings (`u8(u16(810))`, `u16(u32(70000))`,
## `u32(u64(4294967338))`), freezing a silent wrong value into the corpus oracle (#872). Those three now
## sit inside `unchecked`, where the wrap is the defined result; exit codes are mod-256, so the wrap is
## divided into the low byte: u8(810)=42→/4=10; u16(70000)=4464→/1488=3; u32(4294967338)=42→/42=1.
## (Un-narrowed these would divide to 202 / 47 / big.) The checked in-range cases keep their value:
## u8(200)=200, i8(-100)=-100, u32(70000)=70000 from wider declared types. 10 + 3 + 1 + 28 = 42.
## `test/int_narrow_conv_trap.al` holds a checked out-of-range form (a signed source), which traps;
## `test/reject_int_narrow_conv_literal.al` keeps the refused literal spellings (§9.1, #564).
main := fn() -> u64 {
  w16 : u16 = 810
  w32 : u32 = 70000
  w64 : u64 = 4294967338
  a := u64(unchecked u8(w16)) / 4
  b := u64(unchecked u16(w32)) / 1488
  c := u64(unchecked u32(w64)) / 42
  p : u16 = 200
  q : i64 = 0 - 100
  r : u64 = 70000
  ok := u64(u8(p)) == 200 and i64(i8(q)) == 0 - 100 and u64(u32(r)) == 70000
  if not ok { return 1 }
  a + b + c + 28
}
