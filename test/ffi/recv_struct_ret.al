## FFI (increment 3b): an exported `@abi(c)` fn RETURNING a <=16B INTEGER struct to C. SysV delivers
## Pt{i64,i64} in %rax:%rdx (INTEGER class). The C stub `drivemk` calls `alt_mkpt(30, 12)` and sums
## the fields (30 + 12 = 42). Round-trip Alatyr -> C -> Alatyr = 42.
Pt := struct { x : i64, y : i64 }

@export("alt_mkpt") alt_mkpt := @abi(c) fn(a : i64, b : i64) -> Pt { Pt(x = a, y = b) }

drivemk := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drivemk())
}
