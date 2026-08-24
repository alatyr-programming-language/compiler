## asm() {i} immediate substitution on RISC-V 64: {0} → the bare decimal value. Raw exit(42): a0 = 42,
## a7 = 93 (exit), ecall — built with {i}-substituted immediates.
main := fn() -> u64 {
  asm("li a0, {0}", 42)
  asm("li a7, {0}", 93)
  asm("ecall")
  0
}
