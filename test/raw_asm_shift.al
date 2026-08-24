## Register-form shift instructions (spec ch.80 §2): shlq/shrq/sarq(reg, imm) — shift-by-immediate,
## the common form (dest-first -> AT&T `<mnem> $imm, %reg`). In a naked fn: a=%rdi. 21<<1=42, then
## AND 255 (no-op) leaves 42 in %rax; a separate shrq/sarq round-trip is exercised on rcx.
shifty := @abi(naked) fn(a : i64) -> i64 {
  movq(rax, rdi)
  shlq(rax, 1)
  movq(rcx, rax)
  shlq(rcx, 4)
  shrq(rcx, 4)
  sarq(rcx, 0)
  movq(rax, rcx)
  ret()
}
main := fn() -> u64 {
  shifty(21)
}
