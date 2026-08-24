## ROADMAP raw-asm surface (spec ch.80 §2/§6, I4): raw x86_64 instruction intrinsics over REGISTER
## operands — `movq(<reg>, <imm>)` (destination-first → AT&T `movq $imm, %reg`) and `syscall()`. Here a
## naked exit(42): rax=60 (SYS_exit), rdi=42 (code), syscall → the process exits 42 (checked by exit
## code — the syscall side-effect, not a normal return). x86_64-only first slice (registered via
## run_x86 so the wasm/aarch64/riscv64 sweeps skip it — their register surface is a follow-up).
main := fn() -> u64 {
  movq(rax, 60)
  movq(rdi, 42)
  syscall()
  return 0
}
