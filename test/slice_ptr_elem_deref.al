## Priority-1 soundness: an INLINE `deref(s[i]).field` over a Slice(ptr(mut T)) element must read the
## RIGHT field (was silently 0 / segfault — pointee type metadata absent, field fell to `pushq $0`).
## The element POINTER VALUE was already correct; only the inline deref-field select was wrong.
Box := struct { v : u64, w : u64 }
main := fn() -> u64 {
  mut b0 := Box(v = 10, w = 100)
  mut b1 := Box(v = 12, w = 200)
  mut b2 := Box(v = 20, w = 300)
  arr := [ptr(mut b0), ptr(mut b1), ptr(mut b2)]
  s := arr[0..3]
  ## `.len` on a pointer-element slice VIEW must be the ELEMENT COUNT (hi - lo), like a scalar slice.
  if s.len != 3 { return 0 }
  mut sum := 0
  for i in 0..s.len {                  ## the IDIOMATIC loop bound — must read len == 3, not garbage
    sum = sum + deref(s[i]).v          ## 10 + 12 + 20 = 42 (field at offset 0)
  }
  ## also exercise an offset != 0 field: deref(s[0]).w == 100
  chk := deref(s[0]).w                 ## 100
  if chk != 100 { return 0 }
  return sum
}
