## FFI (increment 3b): an exported `@abi(c)` fn RETURNING an all-FLOAT <=16B struct to C. SysV
## delivers D{f64,f64} in %xmm0:%xmm1 (SSE class) — the classed-return remap moves the internal
## %rax:%rdx result words into the SSE result registers. `alt_mkd` SWAPS its args (a=y, b=x) so the
## returned words differ from the incoming %xmm0/%xmm1 (which otherwise pass through untouched and
## would mask a missing remap). `drivemkd` calls `alt_mkd(6.0, 12.0)` and computes d.a*3 + d.b =
## 12*3 + 6 = 42 (a swapped, non-commutative combine). Round-trip Alatyr -> C -> Alatyr = 42.
D := struct { a : f64, b : f64 }

@export("alt_mkd") alt_mkd := @abi(c) fn(x : f64, y : f64) -> D { D(a = y, b = x) }

drivemkd := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drivemkd())
}
