## REGALLOC COMMIT 5 — a value live across TWO sequential calls. `keep` is defined before both calls and
## used after both, so it spans two caller-saved clobbers; `x` (the first result) is also live across the
## SECOND call. Both must be in callee-saved registers / spill slots, never a caller-saved reg. If either
## were corrupted by a call, the sum would be wrong. 30+6 + add(2,2) + add(1,1) = 36 + 4 + 2 = 42. Same
## answer under default (regalloc) and ALATYR_RA=0 (text path).
add := fn(a : u64, b : u64) -> u64 { a + b }
main := fn() -> u64 {
  keep := 30 + 6
  x := add(2, 2)
  y := add(1, 1)
  keep + x + y
}
