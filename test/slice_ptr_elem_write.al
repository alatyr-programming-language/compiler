## Priority-1 soundness: a WRITE `deref(s[i]).field = v` through a POINTER element of a slice (eek 7,
## from a `[ptr(mut b0), …]` literal) must TAKE — was silently DROPPED (the store dual of the inline
## read; `field_slot` returned -1 for a `Deref(Index…)` base → a store to `-0(%rbp)`, a no-op).
Box := struct { v : u64, w : u64 }
main := fn() -> u64 {
  mut b0 := Box(v = 1, w = 0)
  mut b1 := Box(v = 2, w = 0)
  mut b2 := Box(v = 3, w = 0)
  arr := [ptr(mut b0), ptr(mut b1), ptr(mut b2)]
  s := arr[0..3]
  for i in 0..s.len { deref(s[i]).v = 14 }     ## loop write (field at offset 0)
  deref(s[0]).w = 100                          ## single write, offset != 0 field
  ## b0={14,100} b1={14,0} b2={14,0} → 14*3 + 100 - 100 = 42; verifies each write took.
  return b0.v + b1.v + b2.v + b0.w - 100
}
