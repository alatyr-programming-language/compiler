## asm("<GAS>") raw escape on RISC-V 64 (spec ch.80 §4/§11): each call emits its RV64-GAS template
## @target(riscv64) — the asm() body below is RISC-V GAS; a walk on another backend is NOT a divergence (#1041, CG-3: the raw escape is validated only by `as`).
## verbatim as one line (validated only by `as`) — the arch-agnostic escape hatch. A raw exit(42):
## a0 = code, a7 = 93 (the RV64 exit syscall), ecall. The ecall exits before the trailing `0`.
main := fn() -> u64 {
  asm("li a0, 42")
  asm("li a7, 93")
  asm("ecall")
  0
}
## expect(riscv64): run 42
