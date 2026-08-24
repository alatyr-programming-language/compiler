## FFI (spec 50 §7.3): a C-VARIADIC @abi(c) call. `sumv` lives in test/ffi/variadic_int.c and takes
## one fixed `long n` (the count) then `n` trailing `long` varargs read via <stdarg.h> va_arg. The
## `args : ...` bare trailing-rest under @abi(c) is the C-variadic form (NOT the comptime tuple). The
## SysV C ABI places the fixed n in %rdi and the three variadic longs in %rsi/%rdx/%rcx (integer arg
## regs), and requires %al = 0 (no XMM args used). Wrapped in `unchecked` (I11: C-variadics are
## forbidden in checked code). x86_64-only, so run_ffi is sweep-excluded.
sumv := @extern @abi(c) fn(n : i64, args : ...) -> i64

main := fn() -> u64 {
  r := unchecked sumv(3, 10, 15, 17)   ## 10 + 15 + 17 = 42
  return u64(r)
}
