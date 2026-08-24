## FFI: SSE-class and MIXED struct-by-value ARGS at an @abi(c) call (spec 150 §FN-9). dsum/usemix
## live in test/ffi/struct_float_arg.c. SysV classes an all-double struct D{x,y} into TWO SSE
## eightbytes (d.x -> %xmm0, d.y -> %xmm1) and a mixed M{i64, f64} into one INTEGER + one SSE
## eightbyte (m.i -> %rdi, m.d -> %xmm0 — independent counters). dsum(d) = d.x - d.y and
## usemix(m) = m.i - (long)m.d are ORDER/CLASS-sensitive: a swapped eightbyte or an int-in-xmm
## (or float-in-gpr) mapping yields a different exit.
D := struct { x : f64, y : f64 }
M := struct { i : i64, d : f64 }

dsum   := @extern @abi(c) fn(d : D) -> f64
usemix := @extern @abi(c) fn(m : M) -> i64

main := fn() -> u64 {
  d := D(x = 30.0, y = 5.0)   ## dsum -> 30.0 - 5.0 = 25.0
  m := M(i = 20, d = 3.0)     ## usemix -> 20 - 3 = 17
  return u64(dsum(d)) + u64(usemix(m))   ## 25 + 17 = 42
}
