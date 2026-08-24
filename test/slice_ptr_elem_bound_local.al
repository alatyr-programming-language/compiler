## Priority-1 soundness: `p := s[i]` over a POINTER-element slice (eek 7) must INFER `p : ptr(mut <pointee>)`
## (ek 7) so a later `deref(p).field` resolves — was bound scalar → `deref(p).field` read 0. The pointer
## VALUE was already right (an explicit `p : ptr(mut Box) = s[i]` worked); only the INFERRED type was missing.
Box := struct { v : u64, w : u64 }
main := fn() -> u64 {
  mut b0 := Box(v = 10, w = 1)
  mut b1 := Box(v = 12, w = 1)
  mut b2 := Box(v = 20, w = 1)
  arr := [ptr(mut b0), ptr(mut b1), ptr(mut b2)]
  s := arr[0..3]
  mut sum := 0
  for i in 0..s.len {
    p := s[i]                          ## inferred ptr(mut Box) — no annotation
    sum = sum + deref(p).v + deref(p).w   ## (10+12+20) + (1+1+1) = 45
  }
  return sum - 3                       ## 42
}
