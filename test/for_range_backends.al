## e2e (RANGE `for i in lo..hi { … }` on the scalar-kernel backends). Before this, the non-x86 backends
## (aarch64 / riscv64 / wat) had NO `Stmt::For` arm — every for-loop program hit the fail-loud fallback
## and TRAPPED. This is a plain counted range with a scalar body: sum 0..9 (= 36), then + 6 = 42. No
## `continue`, no iterable form — the minimal shape the range lowering must get right on every backend.
main := fn() -> u64 {
  mut s : u64 = 0
  for i in 0..9 { s = s + i }   ## 0+1+...+8 = 36
  s + 6                          ## 42
}
