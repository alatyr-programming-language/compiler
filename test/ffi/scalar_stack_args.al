## FFI (increment 3c): SysV register-OVERFLOW scalar STACK args at an @abi(c) call. add8 lives in
## test/ffi/scalar_stack_args.c. SysV passes the first 6 integer args in %rdi..%r9; args 7 and 8
## spill onto the STACK (arg7 at the lowest address = 0(%rsp), arg8 above it). add8 sums all eight,
## so a mis-placed / mis-ordered stack slot yields a wrong exit. 1+2+3+4+5+6+7+14 = 42.
add8 := @extern @abi(c) fn(a : i64, b : i64, c : i64, d : i64, e : i64, f : i64, g : i64, h : i64) -> i64

main := fn() -> u64 {
  return u64(add8(1, 2, 3, 4, 5, 6, 7, 14))
}
