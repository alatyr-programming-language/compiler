## Register-form imulq (2-operand multiply) + negq/notq (1-operand). In a naked fn: a=%rdi. Compute
## 6*7=42 via imulq, then a negq/notq round-trip on rcx that leaves rax untouched.
compute := @abi(naked) fn(a : u64) -> u64 {
  movq(rax, 6)
  movq(rbx, 7)
  imulq(rax, rbx)
  movq(rcx, 5)
  negq(rcx)
  notq(rcx)
  ret()
}
main := fn() -> u64 {
  compute(0)
}
## expect(x86_64): run 42
