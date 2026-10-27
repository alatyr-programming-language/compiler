## asm("<GAS>") raw escape on AArch64 (spec ch.80 §4/§11): each call emits its AArch64-GAS template
## @target(aarch64) — the asm() body below is AArch64 GAS; a walk on another backend is NOT a divergence (#1041, CG-3: the raw escape is validated only by `as`).
## verbatim as one line (validated only by `as`) — the arch-agnostic escape hatch. A raw exit(42):
## x0 = code, x8 = 93 (the AArch64 exit syscall), svc #0. The svc exits before the trailing `0`.
main := fn() -> u64 {
  asm("mov x0, #42")
  asm("mov x8, #93")
  asm("svc #0")
  0
}
