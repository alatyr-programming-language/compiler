## IR slice 3a (`docs/ir-slice-3.md` §1, #713): `size(T)` and `align(T)` of a scalar type and of a
## struct the builder lays out are `const`s from `lower_layout` (`docs/ir.md` §4), the values x86_64's
## fold answers. Answers 42 everywhere.
P := struct { a : i64, b : u8, c : u16 }
main := fn() -> u64 {
  mut r : u64 = 0
  if size(u8) == 1 { r = r + 1 }
  if size(u16) == 2 and align(u16) == 2 { r = r + 2 }
  if size(i64) == 8 and align(i64) == 8 { r = r + 4 }
  if size(P) == 24 { r = r + 8 }
  if align(P) == 8 { r = r + 16 }
  r + 11
}
