## ROADMAP raw-asm surface (spec ch.80 §2/§6): register-form arithmetic — `addq(dest, src)` (dest += src,
## destination-first → AT&T `addq %src, %dest`). Compute 40 + 2 = 42 in %rdi, then raw exit(42):
## rdi=40, rbx=2, addq(rdi, rbx) → rdi=42; rax=60 (SYS_exit), syscall → exit 42.
main := fn() -> u64 {
  movq(rdi, 40)
  movq(rbx, 2)
  addq(rdi, rbx)
  movq(rax, 60)
  syscall()
  return 0
}
