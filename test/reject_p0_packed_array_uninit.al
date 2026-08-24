## P0 / Types §8: an uninitialized array declaration still has a declared
## @packed element type. Its word-strided fallback cannot represent the
## byte-precise element stride, so lower must reject it rather than silently
## reading the wrong field offset.
P := @packed struct { a : u8, b : u32 }

main := fn() -> u64 {
  mut xs : [P; 1]
  xs[0] = P(a = 1, b = 10)
  if xs[0].b != 10 { return 1 }
  return 42
}
