## raw-asm source operands that spec ch.80 §2/§6 DOES admit, all three in one body, beside the forms
## `reject_raw_asm_operand_*` refuse: a bare decimal (`40`), a negative literal (`-1` — the parser
## folds the unary minus into a single `Num`, which is why it was never part of the #659 defect), and
## a `true` boolean literal. 40 - 1 + 1 + 2 = 42, delivered by a raw exit. This row is the CONTRAST
## that keeps the refusal from being vacuous: if the operand check over-fires, it lands here first.
main := fn() -> u64 {
  movq(rdi, 40)
  movq(rbx, -1)
  addq(rdi, rbx)
  movq(rcx, true)
  addq(rdi, rcx)
  movq(rdx, 2)
  addq(rdi, rdx)
  movq(rax, 60)
  syscall()
  return 0
}
