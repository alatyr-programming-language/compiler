## CLAYOUT S3(d) — a pointer-derived ordinary struct field keeps byte-array layout.
## The field is inline in the pointee, so `deref(p).data[1]` must address one byte,
## not word 1 of the containing struct.
S := struct { data : [u8; 4], tail : u64 }

main := fn() -> u64 {
  mut s := S(data = [0, 0, 0, 0], tail = 7)
  p := ptr(mut s)
  deref(p).data[1] = 42
  if u64(s.data[1]) != 42 { return 1 }
  if u64(deref(p).data[1]) != 42 { return 2 }
  if s.tail != 7 { return 3 }
  42
}
