## e2e — NON-NATIVE integer width conversions TRUNCATE/WRAP (§4). `uN(x)` zero-extends the low N bits,
## `iN(x)` sign-extends — the wrap semantics. Exit codes are mod-256, so the wrap is invisible directly;
## divide to lift the high bits into the low byte. u8(810)=42→/4=10; u16(70000)=4464→/1488=3;
## u32(4294967338)=42→/42=1. 10 + 3 + 1 + 28 = 42. (Un-narrowed these would divide to 202 / 47 / big.)
##
## Each wrapped operand is a VALUE in the next wider type, not the bare out-of-range literal this row
## used to write. Types §9.1 (#564) makes `u8(810)`, `u16(70000)` and `u32(4294967338)` compile errors
## through the `T(v)` spelling, so keeping them here and asserting 42 would have frozen the very
## silent wrap this compiler now refuses into the corpus oracle — the #527 class. Every literal below
## IS representable in its own target type (810 in u16, 70000 in u32, 4294967338 in u64), and §4.2's
## narrowing of a VALUE is the rule the header above always described. The wrap and all three
## quotients are unchanged; the emitted narrowing gains one movzwq/movl for the added widening step.
## `test/reject_int_narrow_conv_literal.al` keeps the refused literal spellings.
main := fn() -> u64 {
  a := u64(u8(u16(810))) / 4
  b := u64(u16(u32(70000))) / 1488
  c := u64(u32(u64(4294967338))) / 42
  a + b + c + 28
}
