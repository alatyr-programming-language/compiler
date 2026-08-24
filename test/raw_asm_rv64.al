## asm("<GAS>") raw escape on RISC-V 64 (spec ch.80 §4/§11): each call emits its RV64-GAS template
## verbatim as one line (validated only by `as`) — the arch-agnostic escape hatch. A raw exit(42):
## a0 = code, a7 = 93 (the RV64 exit syscall), ecall. The ecall exits before the trailing `0`.
main := fn() -> u64 {
  asm("li a0, 42")
  asm("li a7, 93")
  asm("ecall")
  0
}
