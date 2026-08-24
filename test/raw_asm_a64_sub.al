## asm() {i} immediate substitution on AArch64: {0}/{1} → the bare decimal value of the operand (the
## template supplies `#`). Raw exit(42): x0 = 42, x8 = 93, svc #0 — built with {i}-substituted immediates.
main := fn() -> u64 {
  asm("mov x0, #{0}", 42)
  asm("mov x8, #{0}", 93)
  asm("svc #0")
  0
}
