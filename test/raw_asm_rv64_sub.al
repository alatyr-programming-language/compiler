## asm() {i} immediate substitution on RISC-V 64: {0} → the bare decimal value. Raw exit(42): a0 = 42,
## @target(riscv64) — the asm() body below is RISC-V GAS; a walk on another backend is NOT a divergence (#1041, CG-3: the raw escape is validated only by `as`).
## a7 = 93 (exit), ecall — built with {i}-substituted immediates.
main := fn() -> u64 {
  asm("li a0, {0}", 42)
  asm("li a7, {0}", 93)
  asm("ecall")
  0
}
