## fmt — unary minus round-trips as `-x`, not the parser desugar `unchecked 0 - x` (§5 tooling). Both a
## negative LITERAL (`-100`) and a negated VAR (`-a`) must re-emit with the `-` prefix and stay idempotent
## (fmt(fmt(x)) == fmt(x)), and the reformatted source still build+run. Unary `-` wraps (unchecked), so on
## u64: -100 = 2^64-100, -(-100) = 100, 100 - 58 = 42.
main := fn() -> u64 {
  a := -100
  b := -a
  return u64(b - 58)
}
