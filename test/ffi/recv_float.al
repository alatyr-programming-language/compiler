## FFI (increment 3b): an exported `@abi(c)` fn with FLOAT params called from C. `alt_subd` reads
## a,b from %xmm0,%xmm1 (SSE class) and returns in %xmm0. The C stub `drivef` calls
## `alt_subd(50.5, 8.5)` = 42.0 and truncates to 42. Round-trip Alatyr -> C -> Alatyr = 42.
@export("alt_subd") alt_subd := @abi(c) fn(a : f64, b : f64) -> f64 { a - b }

drivef := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drivef())
}
