## e2e: f64 literals + arithmetic (+, -, *, /) + the int↔float conversions f64(i) / u64(f).
## Floats ride the ordinary word-sized value stack as IEEE-754 bits; arithmetic uses the xmm
## regs (addsd/subsd/mulsd/divsd), a literal's bits come from a `.double` the assembler computes,
## f64(i) is cvtsi2sd, u64(f) is the truncating cvttsd2si. Expected process exit: 13.
##   a*b      = 3.5 * 2.0 = 7.0  -> u64 = 7
##   n/b      = 10.0 / 2.0 = 5.0 -> u64 = 5  (n built via f64(10), the int→float conversion)
##   a - b    = 3.5 - 2.0 = 1.5  -> u64 = 1  (truncation)
##   total                            = 13
main := fn() -> u64 {
  a : f64 = 3.5
  b : f64 = 2.0
  n : f64 = f64(10)
  s : f64 = a * b
  q : f64 = n / b
  return u64(s) + u64(q) + u64(a - b)
}
