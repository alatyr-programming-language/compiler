## FFI (increment 3c, RECEIVING side): an exported `@abi(c)` fn taking a MEMORY-class (> 16-byte)
## struct BY VALUE from C. SysV passes a 24-byte struct ON THE STACK (not in registers); the callee
## reads b.a/b.b/b.c from the caller's stack argument area (16 + 8*k(%rbp)). The C stub `drivebig`
## calls alt_sumbig({50, 17, 25}) = 50 + 17 - 25 = 42. Round-trip Alatyr -> C -> Alatyr.
Big := struct { a : i64, b : i64, c : i64 }

@export("alt_sumbig") alt_sumbig := @abi(c) fn(b : Big) -> i64 { b.a + b.b - b.c }

drivebig := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drivebig())
}
