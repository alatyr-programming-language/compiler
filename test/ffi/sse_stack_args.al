## FFI (increment 3c): SysV register-OVERFLOW float STACK args at an @abi(c) call. addf9 lives in
## test/ffi/sse_stack_args.c. SysV passes the first 8 f64 args in %xmm0..%xmm7; the 9th spills onto
## the STACK (at 0(%rsp)). addf9 sums all nine, so a mis-placed 9th slot yields a wrong exit.
## 1+2+3+4+5+6+7+8+6 = 42.
addf9 := @extern @abi(c) fn(a : f64, b : f64, c : f64, d : f64, e : f64, f : f64, g : f64, h : f64, i : f64) -> f64

main := fn() -> u64 {
  return u64(addf9(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 6.0))
}
