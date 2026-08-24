## P3-RA-AGG bounded parent seam: direct Slice(u8) aggregate param plus scalar/control.
## The RA path must byte-load each element (not qword-load the byte buffer), while the index
## helper intentionally remains the existing text path as a skipped seam control.

Slice := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }

sum_u8 := fn(s : Slice(u8), limit : u64) -> u64 {
  mut acc : u64 = 0
  for x in s {
    if acc < limit { acc = acc + x }
  }
  acc
}

read_index := fn(s : Slice(u8), i : usize) -> u64 { return s[i] }

main := fn() -> u64 {
  mut b : [u8; 4] = [2, 3, 5, 7]
  s := Slice(u8)(ptr = ptr(b[0]), len = 4)
  if read_index(s, 2) != 5 { return 1 }
  sum_u8(s, 100)
}
