## @abi(naked) fn on AArch64 (spec ch.80): raw body via asm(), no prologue/epilogue. System V AArch64:
## @target(aarch64) — the asm() body below is AArch64 GAS; a walk on another backend is NOT a divergence (#1041, CG-3: the raw escape is validated only by `as`).
## args in x0/x1, result in x0. add2(40, 2) = 42, closed by asm("ret").
add2 := @abi(naked) fn(a : i64, b : i64) -> i64 {
  asm("add x0, x0, x1")
  asm("ret")
}
main := fn() -> u64 {
  add2(40, 2)
}
