## e2e / a64 NON-X86 BREADTH — an ENUM LOCAL passed as a call ARGUMENT is passed BY REFERENCE (the
## callee's enum param slot holds a POINTER to the caller's {disc, payload…} block, which the callee's
## `match` derefs). On a64 the argument path only knew struct / array / slice locals, so an enum local
## fell through to the SCALAR path and its word 0 — the DISCRIMINANT — was passed AS the pointer: the
## callee dereferenced 0 and the program died of a RAW SIGSEGV (exit 139), not a clean `brk`. It also
## exercises the A64_MTMP reservation for a `match <enum PARAM>`: nothing sized that region, so the
## materialization wrote past the frame top into the CALLER's frame (for the 11-word `W` it clobbered
## the caller's saved x29/x30 and the source block itself).
##
## `N` is a narrow 3-word enum, `W` an 11-word one (> the 8-word register-return budget, so `mkW` also
## delivers via the x8 indirect result). Each payload word is DISTINCT and the readers take the FIRST,
## a MIDDLE, the LAST and a second interior pair, so a dropped / zeroed / swapped word changes the
## answer: (10 + 11) + ((1 + 5 + 10) + (8 - 2)) = 21 + 22 = 43. Stays < 126 (WASI proc_exit range).
N := enum { Two(u64, u64), None }
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

sumN := fn(n : N) -> u64 {
  match n {
    N::Two(a, b) => a + b
    N::None => 0
  }
}
sumW := fn(w : W) -> u64 {
  match w {
    W::Many(a, b, c, d, e, f, g, h, i, j) => (a + e + j) + (h - b)
    W::Small(x) => 0
  }
}
mkW := fn(base : u64) -> W {
  return W.Many(base, base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7, base + 8, base + 9)
}

main := fn() -> u64 {
  n := N.Two(10, 11)
  w := mkW(1)
  sumN(n) + sumW(w)     ## 21 + 22 = 43
}
