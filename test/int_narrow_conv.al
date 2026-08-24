## e2e — NON-NATIVE integer width conversions TRUNCATE/WRAP (§4). `uN(x)` zero-extends the low N bits,
## `iN(x)` sign-extends — the wrap semantics. Exit codes are mod-256, so the wrap is invisible directly;
## divide to lift the high bits into the low byte. u8(810)=42→/4=10; u16(70000)=4464→/1488=3;
## u32(4294967338)=42→/42=1. 10 + 3 + 1 + 28 = 42. (Un-narrowed these would divide to 202 / 47 / big.)
main := fn() -> u64 {
  a := u64(u8(810)) / 4
  b := u64(u16(70000)) / 1488
  c := u64(u32(4294967338)) / 42
  a + b + c + 28
}
