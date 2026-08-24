## FFI: a MEMORY-class struct RETURN (> 16 bytes) at an @abi(c) call (spec 150 §FN-9, increment 3a).
## mkbig lives in test/ffi/struct_big_ret.c. SysV returns a struct > 16 bytes (Big = 24 bytes) via
## SRET: the caller allocates the destination local (q), passes its ADDRESS as the hidden first integer
## arg (%rdi), shifting the real args a -> %rsi, b -> %rdx, c -> %rcx; the callee writes {a, b, c}
## straight into q and returns the pointer in %rax. All three returned fields are read back and combined
## by q.a - q.b + q.c (a mis-placed field / wrong sret pointer yields a different exit).
Big := struct { a : i64, b : i64, c : i64 }

mkbig := @extern @abi(c) fn(a : i64, b : i64, c : i64) -> Big   ## {a, b, c} written through the sret ptr

main := fn() -> u64 {
  q := mkbig(50, 20, 12)          ## q.a = 50, q.b = 20, q.c = 12
  return u64(q.a - q.b + q.c)     ## 50 - 20 + 12 = 42
}
