## Nested for over Slice(u8) elements of an array — the slice length must survive the outer
## element binding. Three shapes: local array, slice parameter with for, slice parameter with while.
## Parent: 0 at 2cf60b45 (the outer for read a stale length). Refs #1181.
lens := fn(xs : Slice(Slice(u8))) -> u64 {
  mut n : u64 = 0
  for s in xs { n = n * 10 + u64(s.len) }
  return n
}
lens_while := fn(xs : Slice(Slice(u8))) -> u64 {
  mut n : u64 = 0
  mut i : u64 = 0
  while i < xs.len { n = n * 10 + u64(xs[i].len) ; i += 1 }
  return n
}
main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  t : [Slice(u8); 2] = [a[0..3], b[0..2]]
  mut n : u64 = 0
  for s in t { n = n * 10 + u64(s.len) }
  if n != 32 { return 1 }
  if lens(t[0..2]) != 32 { return 2 }
  if lens_while(t[0..2]) != 32 { return 3 }
  42
}
## expect: run 42
