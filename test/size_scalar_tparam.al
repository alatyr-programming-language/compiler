## Regression: size()/align() of a SCALAR type-param must use the concrete narrow width,
## not the word default. Struct type-param size must stay correct.

gsize := fn(V : type) -> u64 { u64(size(V)) }
galign := fn(V : type) -> u64 { u64(align(V)) }
gsize2 := fn(K : type, V : type) -> u64 { u64(size(V)) }

P2 := struct { a : u64, b : u64 }

main := fn() -> u64 {
  mut acc := u64(0)
  ## scalar sizes across widths
  if gsize(u8) != 1 { return 1 }
  if gsize(u16) != 2 { return 2 }
  if gsize(u32) != 4 { return 3 }
  if gsize(u64) != 8 { return 4 }
  ## scalar alignment
  if galign(u16) != 2 { return 5 }
  if galign(u8) != 1 { return 6 }
  if galign(u64) != 8 { return 7 }
  ## struct type-param size must stay correct (2 words = 16)
  if gsize(P2) != 16 { return 8 }
  ## two-type-param form, sub-word 2nd param
  if gsize2(u8, u16) != 2 { return 9 }
  42
}
