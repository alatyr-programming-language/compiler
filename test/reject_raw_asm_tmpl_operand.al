## #659, the SECOND copy of the same decision: the `asm("…{i}…", op…)` template substitution
## (spec ch.80 §4/§11) read its operand through the same accessor and had the same silent answer.
## The first template here substitutes an accepted literal, so the refusal is located at the `{1}`
## operand of the second and not at the whole escape. Measured on the parent: `check` rc 0,
## `build` rc 0, exit 40 where 39 was due.
main := fn() -> u64 {
  asm("movq {0}, {1}", 40, rdi)
  asm("movq {1}, %rbx", rcx, 0 - 1)
  addq(rdi, rbx)
  movq(rax, 60)
  syscall()
  return 0
}
