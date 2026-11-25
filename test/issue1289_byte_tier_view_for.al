## #1289 — `for q in u[1..3]` over a byte-tier struct array (Types §6.1/§6.4: 2-byte elements) yields
## `u[1]`, `u[2]` in order (Control Flow §6): 3, then 5. NON-VACUOUS: on the parent da8f96af (native
## x86_64, tree Stage1) this answers 1 (`n` was 0) on x86_64, aarch64 and riscv64.
Q := struct { a : u8, b : u8 }
main := fn() -> u64 {
  mut u : [Q; 3] = [Q(a = 1, b = 2), Q(a = 3, b = 4), Q(a = 5, b = 6)]
  qs := u[1..3]
  mut n : u64 = 0
  for q in qs { n = n * 10 + u64(q.a) }
  if n != 35 { return 1 }
  42
}
## expect: run 42
