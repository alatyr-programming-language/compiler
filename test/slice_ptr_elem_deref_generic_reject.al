## GENERIC `deref(s[i]).field` over a `Slice(ptr(mut T))` PARAM: the pointee `T` is erased in the
## param's source text, so the pointee struct span cannot be resolved without per-instance mono
## type-arg machinery. The lower FAILS LOUD (rather than a silent `pushq $0` miscompile — the concrete
## `[ptr(mut b0), …]` case IS supported; see slice_ptr_elem_deref.al). Asserted via `build_reject`.
Box := struct { v : u64, w : u64 }
sumv := fn(T : type, s : Slice(ptr(mut T)), n : usize) -> u64 {
  mut acc := 0
  for i in 0..n { acc = acc + deref(s[i]).v }
  return acc
}
main := fn() -> u64 {
  mut b0 := Box(v = 10, w = 100)
  mut b1 := Box(v = 12, w = 200)
  arr := [ptr(mut b0), ptr(mut b1)]
  s := arr[0..2]
  return sumv(Box, s, 2)
}
