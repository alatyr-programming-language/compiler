## e2e / rv64 NON-X86 BREADTH — a WIDE-enum-returning CALL used directly as a call ARGUMENT
## (`sum(mk(1))`). The callee delivers the {disc, payload…} block through the indirect result pointer,
## and in ARGUMENT position there is no destination local to point it at, so the caller reserves a frame
## block, hands its base down as the result pointer, and then passes that same block BY REFERENCE (the
## aggregate-parameter ABI). Without the reserved block the call reached a callee expecting a result
## pointer with none in scope. `W.Many(...)` = disc + 10 payload = 11 words > the 8-register budget.
## The reader takes the FIRST (word 1), a MIDDLE (word 5) and the LAST (word 10) payload word, so a
## dropped / zeroed / shifted word changes the answer: 1 + 5 + 10 = 16.
##
## NOT yet wired into scripts/e2e.sh: riscv64 and aarch64 both answer 16, but the x86_64 backend dies of
## a RAW SIGSEGV (exit 139) on this shape — a wide-enum-returning call in ARGUMENT position. Add the
## `run enum_sret_wide_arg 16` line once src/lower.al handles it.
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

mk := fn(base : u64) -> W {
  return W.Many(base, base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7, base + 8, base + 9)
}

sum := fn(w : W) -> u64 {
  match w {
    W::Many(a, b, c, d, e, f, g, h, i, j) => a + e + j
    W::Small(x) => 0
  }
}

main := fn() -> u64 {
  sum(mk(1))   ## word1(1) + word5(5) + word10(10) = 16
}
