## e2e (#1272) — an `unchecked` `+ - *` whose operand is a global const wraps at the const's narrow
## type, exactly as with a local operand.
##
## Types §4 value model and I11 (spec v1.6.0): an `unchecked` `+ - *` takes the two's-complement wrap
## at its operand type's width.
##
## Expected: 40 on all four backends.
## Measured on the parent (main 930c4e17, native x86_64): x86_64 kept the 64-bit result and exited 1
## (`A + A` was 2^32 - 2, not -2); the twins exited 40.
A : i32 = 2147483647
B : u8 = 200
C : u16 = 65535

main := fn() -> u64 {
  x : i32 = unchecked (A + A)
  if x != (0 - 2) { return 1 }
  y : u8 = unchecked (B * 2)
  if y != 144 { return 2 }
  z : u16 = unchecked (C + 3)
  if z != 2 { return 3 }
  w : i32 = unchecked (0 - A - A - A)
  if w != (0 - 2147483645) { return 4 }
  return 40
}
