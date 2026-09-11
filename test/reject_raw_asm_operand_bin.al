## #659: a raw-asm register-form instruction whose SOURCE operand is a `Bin` tree. Spec ch.80 §2/§6
## gives the operand grammar as a register name or an immediate literal, so `0 - 1` is not an operand
## form at all. Measured on the parent compiler: `check` rc 0, `build` rc 0, and the program RAN,
## exiting 40 where 39 was due — the operand had silently become the immediate `$0`. The accepted
## `movq(rdi, 40)` stands BEFORE the offending line (the other order is in
## `reject_raw_asm_operand_bin_first`), so a refusal here cannot be a blanket refusal of the whole
## instruction family.
main := fn() -> u64 {
  movq(rdi, 40)
  movq(rbx, 0 - 1)
  addq(rdi, rbx)
  movq(rax, 60)
  syscall()
  return 0
}
