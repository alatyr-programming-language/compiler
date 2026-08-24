## e2e (Grammar §130 line 287 · I11): the MINIMAL silent-wrong-value shape the missing four
## compound-assignment operators produced. Measured on the frozen seed: `check` exits 0 (a
## CLEAN compile, no diagnostic) and the program returns 110 — `x &= 58` lexed as `&` then `=`,
## matched no statement head, was parsed as the trailing return expression, and the STORE was
## discarded, so `x` stayed 100 and `x + 10` came out 110. A silent wrong value.
##
## Expected exit: 42 — 100 & 58 = 32 (0b1100100 & 0b0111010 = 0b0100000), plus 10.
main := fn() -> u64 {
  mut x : u64 = 100
  x &= 58
  return x + 10
}
