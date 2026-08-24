## asm("…GAS…", op…) raw escape (spec ch.80 §4/§11): each call emits its template as one GAS line
## (validated only by `as`) — the escape hatch for any instruction not in the per-arch table. The
## fixed positional-{i} substitution scheme: {0}/{1}/… → operand 0/1/… spelling (a register → %reg,
## an immediate → $N). Here: a raw exit(42) — first two lines use {i} substitution, third is verbatim.
main := fn() -> u64 {
  asm("movq {0}, {1}", 42, rdi)
  asm("movq {0}, {1}", 60, rax)
  asm("syscall")
  0
}
