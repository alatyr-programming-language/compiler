## @abi(naked) fn on RISC-V 64 (spec ch.80): raw body via asm(), no prologue/epilogue. RV64: args in
## a0/a1, result in a0. add2(40, 2) = 42, closed by asm("ret").
add2 := @abi(naked) fn(a : i64, b : i64) -> i64 {
  asm("add a0, a0, a1")
  asm("ret")
}
main := fn() -> u64 {
  add2(40, 2)
}
