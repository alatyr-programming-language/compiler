## FFI (spec 50 §7.3): a C-VARIADIC @abi(c) call MIXING integer + double varargs — exercises the %al
## XMM-count requirement and independent SysV int/SSE variadic arg placement. `mixv` (test/ffi/
## variadic_mixed.c) takes a fixed `long n` then four varargs (long, double, long, double); the two
## doubles ride %xmm0/%xmm1, so %al MUST be 2 — a variadic prologue only spills the XMM registers when
## %al > 0, so a wrong %al reads garbage doubles. Distinct weights (1,2,3,4) make any misordering or
## int/SSE swap change the exit code. Wrapped in `unchecked` (I11). x86_64-only (sweep-excluded).
mixv := @extern @abi(c) fn(n : i64, args : ...) -> i64

main := fn() -> u64 {
  ## n=0 (fixed, %rdi); then 10 -> %rsi, 3.0 -> %xmm0, 4 -> %rdx, 3.5 -> %xmm1 (%al = 2).
  ## 10*1 + (long)(3.0*2) + 4*3 + (long)(3.5*4) = 10 + 6 + 12 + 14 = 42.
  r := unchecked mixv(0, 10, 3.0, 4, 3.5)
  return u64(r)
}
