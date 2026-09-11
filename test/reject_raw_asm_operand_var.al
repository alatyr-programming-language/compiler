## #659, the shape the issue's summary sentence covers but its table did not enumerate: a plain local
## NAME as the source operand. `x` is not a GP register name, so the emitter fell off the register
## side of the operand grammar and onto the immediate side, where the old accessor answered `0`.
## Measured on the parent: `check` rc 0, `build` rc 0, exit 40 where 42 was due.
main := fn() -> u64 {
  x := 2
  movq(rdi, 40)
  movq(rbx, x)
  addq(rdi, rbx)
  movq(rax, 60)
  syscall()
  return 0
}
