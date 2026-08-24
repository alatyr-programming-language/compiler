## e2e — the scalar-IR constant-folding slice. All three bitwise operators have immediate scalar
## operands in the checked default context (bitwise operations have no overflow/trap semantics), so the
## IR pass may replace each `mov; bitop` pair with one immediate `mov`. The e2e helper also checks the
## emitted GAS contains no runtime bitwise instruction and runs the same source with ALATYR_RA=0.
main := fn() -> u64 {
  a := 40 & 2
  b := 40 | 2
  c := 40 ^ 2
  a + b
}
