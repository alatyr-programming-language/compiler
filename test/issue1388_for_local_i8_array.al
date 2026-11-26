## #1388 — the `i8` twin: each element of a `[i8; N]` local is read sign-extended (Types §2.1), so
## `-2` stays -2: 1 * 100 + (-2) * 10 + 3 = 83. NON-VACUOUS: on the parent da8f96af (native x86_64,
## tree Stage1) this built and died with SIGSEGV (139) on x86_64.
main := fn() -> u64 {
  t : [i8; 3] = [1, -2, 3]
  mut n : i64 = 0
  for x in t { n = n * 10 + i64(x) }
  if n != 83 { return 1 }
  42
}
## expect: run 42
