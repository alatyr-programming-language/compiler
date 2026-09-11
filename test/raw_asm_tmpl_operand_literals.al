## The `asm("…{i}…", op…)` template operands spec ch.80 §4/§11 admits, beside the form
## `reject_raw_asm_tmpl_operand` refuses: an immediate literal operand and a REGISTER operand, in one
## template each. rdi = 40, rcx = 2, `addq {0}, {1}` adds rcx into rdi -> 42, then a raw exit(42).
## The contrast row for the template half of #659.
main := fn() -> u64 {
  asm("movq {0}, {1}", 40, rdi)
  asm("movq {0}, {1}", 2, rcx)
  asm("addq {0}, {1}", rcx, rdi)
  asm("movq {0}, {1}", 60, rax)
  asm("syscall")
  0
}
