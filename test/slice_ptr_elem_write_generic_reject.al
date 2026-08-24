## GENERIC WRITE `deref(s[i]).field = v` over a `Slice(ptr(mut T))` PARAM: the pointee `T` is erased, so
## the lower FAILS LOUD (rather than silently dropping the write). Asserted via `build_reject`. The
## concrete `[ptr(mut b0), …]` write IS supported (see slice_ptr_elem_write.al).
Box := struct { v : u64, w : u64 }
setall := fn(T : type, s : Slice(ptr(mut T)), n : usize) {
  for i in 0..n { deref(s[i]).v = 7 }
}
main := fn() -> u64 {
  mut b0 := Box(v = 1, w = 0)
  arr := [ptr(mut b0)]
  s := arr[0..1]
  setall(Box, s, 1)
  return b0.v
}
