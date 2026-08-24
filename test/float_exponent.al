## Focused Grammar §2.4 acceptance/runtime fixture: decimal floating-point exponent forms.
## Both `dec-int exp` and `dec-int "." dec-int exp` preserve their source span through parsing and
## the native `.double` emission. Expected exit: 25 (10.0 + 15.0 + 0.25, each converted to u64).
main := fn() -> u64 {
  a : f64 = 1e1
  b : f64 = 1.5e+1
  c : f64 = 2.5E-1
  return u64(a) + u64(b) + u64(c)
}
