## sema/§ limits (CG-12): a `@limits(no_abstractions)` unit written on the 1:1 assembly surface ACCEPTS
## + builds + runs. `main` is pure instruction intrinsics over register/immediate operands — `movq`
## (destination-first) + `syscall()` — plus a `return` of an immediate: every emitted runtime
## instruction is one written here, 1-to-1 with GAS. A naked exit(42): rax=60 (SYS_exit), rdi=42.
@limits(no_abstractions)
main := fn() -> u64 {
  movq(rax, 60)
  movq(rdi, 42)
  syscall()
  return 0
}
