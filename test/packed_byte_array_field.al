## P1-BYTES — an explicitly typed byte fixed-array FIELD in an @packed struct.
## The field uses the packed struct's byte layout: bind/size, construction, indexed
## read/write, ptr(element) addressing, and a proven word-padded aggregate copy.
U := @packed struct { tag : u8, data : [u8; 4], tail : u8 }
I := @packed struct { data : [i8; 3], tail : i8 }
B := @packed struct { data : [bits8; 2], tail : bits8 }

main := fn() -> u64 {
  mut u := U(tag = 7, data = [10, 20, 30, 40], tail = 9)
  copy := u
  mut i := I(data = [-1, 2, 3], tail = 4)
  b := B(data = [5, 6], tail = 7)
  p0 := unchecked bitcast(usize, ptr(u.data[0]))
  p1 := unchecked bitcast(usize, ptr(u.data[1]))
  p3 := unchecked bitcast(usize, ptr(u.data[3]))
  u.data[1] = 42
  if p1 - p0 != 1 { return 2 }
  if p3 - p0 != 3 { return 3 }
  if u.data[0] != 10 { return 4 }
  if u.data[1] != 42 { return 5 }
  if u.data[3] != 40 { return 6 }
  if copy.data[2] != 30 { return 7 }
  if i.data[0] >= 0 { return 8 }
  if i.data[1] != 2 { return 9 }
  if b.data[0] != 5 { return 10 }
  if b.data[1] != 6 { return 11 }
  if size(U) != 6 { return 12 }
  if align(U) != 1 { return 13 }
  return 42
}
