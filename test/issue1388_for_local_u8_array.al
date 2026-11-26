## #1388 — `for x in t` over a byte-element fixed-array LOCAL yields its elements in order (Control
## Flow §6; I11): 1, 2, 3. NON-VACUOUS: on the parent da8f96af (native x86_64, tree Stage1) this built
## and died with SIGSEGV (139) on x86_64; aarch64, riscv64 and wasm answered 42.
main := fn() -> u64 {
  t : [u8; 3] = [1, 2, 3]
  mut n : u64 = 0
  for x in t { n = n * 10 + u64(x) }
  if n != 123 { return 1 }
  42
}
## expect: run 42
