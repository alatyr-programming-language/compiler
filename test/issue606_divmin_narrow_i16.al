## I11 / CG-8 + CG-13, Concurrency §6.1 — the `i16` width of the narrow `MIN / -1` division
## overflow. `i16`'s minimum is -32768 and the quotient +32768 is not representable, so the
## family's direct inline trap is due BEFORE the divide (132 / 133 / 133 / 134 across the four
## backends). This width exists as its own fixture because each backend materializes the bound
## differently: the 64-bit MIN the parent compared against is a single wide immediate, while
## -32768 is a different encoding on every target, and a fix that hard-codes one width leaves the
## others silently answering an unrepresentable value.
##
## PARENT BEHAVIOUR (all four backends, exit 60): the quotient was 32768, outside `i16`, so the
## `q <= 32767` test that holds for every `i16` was not taken. 61 would be the 16-bit wrap -32768
## and 62 any other in-range quotient; no arm compares against a literal outside `i16`.
main := fn() -> u64 {
  v : i16 = 0 - 32768
  d : i16 = 0 - 1
  q := v / d
  if q <= 32767 {
    if q == 0 - 32768 { return 61 }
    return 62
  }
  return 60
}
