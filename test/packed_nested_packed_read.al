## CLAYOUT boundary: a @packed root containing a @packed nested child.
## The root has a byte-array prefix so a standard_field_path resolver must not
## steal the root from the packed byte-cursor path. Inner itself is packed:
## a @0 (u8), b @1 (u16), and the root places Inner at byte 8.
Inner := @packed struct { a : u8, b : u16 }
Outer := @packed struct { data : [u8; 8], inner : Inner }

main := fn() -> u64 {
  o := Outer(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Inner(a = 20, b = 22))
  if o.inner.a != 20 { return 1 }
  if o.inner.b != 22 { return 2 }
  if o.data[1] != 2 { return 3 }
  if o.data[7] != 8 { return 4 }
  42
}
