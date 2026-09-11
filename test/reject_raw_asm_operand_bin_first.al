## #659, the other order: the offending `Bin` operand comes FIRST, with the accepted literal operands
## after it, so the refusal cannot depend on having already emitted a well-formed instruction.
## Measured on the parent: `check` rc 0, `build` rc 0, exit 40 where 42 was due (`1 + 1` became `$0`).
main := fn() -> u64 {
  movq(rbx, 1 + 1)
  movq(rdi, 40)
  addq(rdi, rbx)
  movq(rax, 60)
  syscall()
  return 0
}
