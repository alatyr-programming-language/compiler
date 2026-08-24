## FFI: a scalar @abi(c) call. add3 lives in test/ffi/scalar_call.c; SysV passes a,b,c in
## rdi/rsi/rdx — which is exactly our internal ABI for scalars, so this validates the harness.
add3 := @extern @abi(c) fn(a : i64, b : i64, c : i64) -> i64

main := fn() -> u64 {
  return u64(add3(20, 15, 7))
}
