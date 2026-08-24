## Proposal #2 / scalar-IR fold-3: unchecked native logical shifts with immediate value/count fold
## around the implicit `%rcx` count move. The result is 17 << 1 + 17 >> 1 = 34 + 8 = 42.
main := fn() -> u64 {
  a := unchecked shl(17, 1)
  b := unchecked shr(17, 1)
  a + b
}
