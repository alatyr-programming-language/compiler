## Register-form logic instructions (spec ch.80 §2): andq/orq/xorq over registers, alongside movq.
## Inside a naked fn: a=%rdi. mask with 255 (no-op for 42), OR 0 (no-op), self-xor rcx to 0 then
## XOR (no-op) — result stays 42 in %rax.
logic := @abi(naked) fn(a : i64) -> i64 {
  movq(rax, rdi)
  movq(rbx, 255)
  andq(rax, rbx)
  movq(rcx, 0)
  orq(rax, rcx)
  xorq(rcx, rcx)
  xorq(rax, rcx)
  ret()
}
main := fn() -> u64 {
  logic(42)
}
