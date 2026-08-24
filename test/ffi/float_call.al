## FFI: float/double SCALAR args + return at an @abi(c) call (spec 150 §FN-9, SysV SSE class).
## subd lives in test/ffi/float_call.c; SysV passes a,b in %xmm0/%xmm1 and returns the double in
## %xmm0. subd(a, b) = a - b is ORDER-SENSITIVE: swapped xmm0/xmm1 would give -42 (a different exit).
subd := @extern @abi(c) fn(a : f64, b : f64) -> f64

main := fn() -> u64 {
  return u64(subd(50.0, 8.0))   ## 50.0 - 8.0 = 42.0 -> 42
}
