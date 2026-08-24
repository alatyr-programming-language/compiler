## e2e (reject) — `_` SEPARATES digits, it may not LEAD them: Grammar §2.4 spells
## `hex-int ::= "0x" hex-digit { hex-digit | "_" }`, so a `_` immediately after the base prefix is
## not a literal. Located reject, never a truncation to `0`.
main := fn() -> u64 {
  x : u64 = 0x_1
  return x
}
