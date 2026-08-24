## e2e / a64 NON-X86 BREADTH — a fn returning an ENUM whose {disc, payload…} total EXCEEDS the 8-word
## register-return budget is delivered via the x8 indirect result (SRET), exactly like a wide struct,
## NOT truncated. `W.Many(...)` = disc + 10 payload = 11 words > 8, so the a64 callee writes the whole
## {disc, payload…} block through x8 into the caller's destination; the caller `match`es it, reading the
## FIRST (word 1), MIDDLE (word 5), and LAST (word 10) payload words. Returns 3 + 15 + 30 = 48.
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

mk := fn() -> W { return W.Many(3, 6, 9, 12, 15, 18, 21, 24, 27, 30) }

main := fn() -> u64 {
  v := mk()
  match v {
    W::Many(a, b, c, d, e, f, g, h, i, j) => a + e + j   ## word1(3) + word5(15) + word10(30) = 48
    W::Small(x) => 0
  }
}
