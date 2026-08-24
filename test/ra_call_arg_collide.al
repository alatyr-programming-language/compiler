## REGALLOC COMMIT 5 — a value that is BOTH a call ARGUMENT and live ACROSS the call. `p` is passed as
## arg0 (loaded into %rdi) AND used after the call, so it cannot stay in %rdi (a caller-saved arg register
## the call clobbers) — it must be held in a callee-saved register and copied into %rdi for the arg. If the
## allocator let `p` live in %rdi across the call, the return value would be wrong. p=16+16=32; add(p,5)=37;
## p + q = 32 + 37 = 69. Same answer under default (regalloc) and ALATYR_RA=0 (text path).
add := fn(a : u64, b : u64) -> u64 { a + b }
main := fn() -> u64 {
  p := 16 + 16
  q := add(p, 5)
  p + q
}
