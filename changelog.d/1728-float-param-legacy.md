- **x86_64: a function with a float parameter is no longer built by the shared IR (#1728).** The
  selectors took the parameter from an integer register while a legacy caller passed it in `%xmm0`, so
  `bits(x : f64)` called from legacy code read the wrong bits. The function, and an IR-built call that
  would pass a float argument, are refused with "signature: floating-point parameter" and stay
  legacy-emitted.
