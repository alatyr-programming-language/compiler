## e2e / a64 NON-X86 BREADTH — wide-enum SRET via a `return <enum LOCAL>` (not a direct literal): the
## callee builds the wide enum in a frame local, then delivers it through the x8 indirect result by
## word-copying the local's slots. `W.Many(...)` = disc + 9 payload = 10 words > 8. The caller binds the
## SRET result to a local (`v := mk()`, sized to the full enum width) and `match`es it, reading the
## FIRST (word 1), MIDDLE (word 5), and LAST (word 9) payload words. Returns 2 + 10 + 18 = 30.
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64), Zero }

mk := fn() -> W {
  e := W.Many(2, 4, 6, 8, 10, 12, 14, 16, 18)
  return e
}

main := fn() -> u64 {
  v := mk()
  match v {
    W::Many(a, b, c, d, e, f, g, h, i) => a + e + i   ## word1(2) + word5(10) + word9(18) = 30
    W::Zero => 0
  }
}
