## I11 / CG-8 + CG-13, Concurrency §6.1 — the `i32` width of the narrow `MIN / -1` division
## overflow, and the widest bound a narrow guard has to materialize. `i32`'s minimum is
## -2147483648; the quotient +2147483648 is not representable, so the direct inline trap is due
## BEFORE the divide (132 / 133 / 133 / 134 across the four backends).
##
## This width is the encoding edge case on aarch64: 128 and 32768 both fit the compare-negative
## immediate forms, 2147483648 does not, so a guard written only against the small immediates would
## pass the `i8`/`i16` fixtures and still let this one through with a value.
##
## PARENT BEHAVIOUR (all four backends, exit 60): the quotient was 2147483648, outside `i32`, so
## the `q <= 2147483647` test that holds for every `i32` was not taken. 61 would be the 32-bit wrap
## and 62 any other in-range quotient; no arm compares against a literal outside `i32`.
main := fn() -> u64 {
  v : i32 = 0 - 2147483648
  d : i32 = 0 - 1
  q := v / d
  if q <= 2147483647 {
    if q == 0 - 2147483648 { return 61 }
    return 62
  }
  return 60
}
