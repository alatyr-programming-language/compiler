## Bounded P3-RA-AGG follow-up: the codec's byte loops widen each byte before
## scalar arithmetic. Native integer conversion is an identity at word width,
## so `u64(x)` should not force this otherwise-supported Slice(u8) loop to text.

Slice := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }

sum_cast := fn(s : Slice(u8)) -> u64 {
  mut acc : u64 = 0
  for x in s { acc = acc + u64(x) }
  acc
}

## Adjacent skipped seam: direct Slice indexing remains text-lowered.
read_index := fn(s : Slice(u8), i : usize) -> u64 { u64(s[i]) }

main := fn() -> u64 {
  mut b : [u8; 4] = [2, 3, 5, 7]
  s := Slice(u8)(ptr = ptr(b[0]), len = 4)
  if read_index(s, 2) != 5 { return 1 }
  sum_cast(s)
}
