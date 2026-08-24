## FN-6 CAPTURE — a MULTI-STATEMENT lambda body (inner `:=` let + a trailing value expression) that
## captures. The lift collects the body's inner LOCALS (`d`) so they are not mistaken for captures, and
## collects the free var `c` over all statements + the tail expr; `c` is appended as a param + injected
## at the call. `d := 16*2 = 32; d + c(10)` = 42. (A `match`-arm-binding body is not analyzed in this
## slice — such a capturing lambda is rejected fail-loud instead.)
main := fn() -> u64 {
  c := 10
  f := fn(n : u64) -> u64 { d := n * 2; d + c }
  return f(16)
}
