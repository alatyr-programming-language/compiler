## e2e / a64 NON-X86 BREADTH — wide-enum SRET where the WIDE variant is NOT discriminant 0 (exercises the
## discriminant write + dispatch, not just payload words). `W.Big(...)` = variant 1, disc + 9 payload =
## 10 words > 8 → x8 indirect result. The caller `match`es on the discriminant (must pick the Big arm,
## not the A arm) and reads the FIRST (word 1), MIDDLE (word 5), and LAST (word 9) payload words.
## Returns 5 + 25 + 45 = 75.
W := enum { A(u64), Big(u64, u64, u64, u64, u64, u64, u64, u64, u64) }

mk := fn() -> W { return W.Big(5, 10, 15, 20, 25, 30, 35, 40, 45) }

main := fn() -> u64 {
  w := mk()
  match w {
    W::A(v) => 0
    W::Big(a, b, c, d, e, f, g, h, i) => a + e + i   ## word1(5) + word5(25) + word9(45) = 75
  }
}
