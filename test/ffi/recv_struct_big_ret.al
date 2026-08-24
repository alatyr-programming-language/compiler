## FFI (increment 3c, RECEIVING side): an exported `@abi(c)` fn RETURNING a MEMORY-class (> 16-byte)
## struct to C via SysV SRET. C passes the destination's address in the hidden %rdi (shifting the real
## args x -> %rsi, y -> %rdx, z -> %rcx); alt_mkbig writes {x, y, z} through it (word k at k*8(%rdi))
## and returns the pointer in %rax. The C stub `drivemkbig` reads r.a - r.b + r.c = 50 - 20 + 12 = 42.
Big := struct { a : i64, b : i64, c : i64 }

@export("alt_mkbig") alt_mkbig := @abi(c) fn(x : i64, y : i64, z : i64) -> Big { Big(a = x, b = y, c = z) }

drivemkbig := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drivemkbig())
}
