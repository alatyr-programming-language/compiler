## Priority-1 soundness: a field access through a NESTED deref (pointer-to-pointer-to-struct),
## `deref(deref(pp)).field`, must READ + WRITE the right field — was silently 0 (read) / a no-op
## (write) because the deref-field pointee resolver had no `deref(<Deref>).f` branch (the pointee-of-
## pointee type wasn't recovered → `pushq $0` / a `-0(%rbp)` store). Depth-2 concrete; deeper nests
## and generic-erased pointees remain unresolved (fall through, not silently claimed).
Box := struct { v : u64, w : u64 }
main := fn() -> u64 {
  mut b := Box(v = 0, w = 0)
  mut p := ptr(mut b)
  pp := ptr(mut p)                     ## pp : ptr(mut ptr(mut Box))
  ## WRITE through the nested deref (field at offset 0 and offset != 0)
  deref(deref(pp)).v = 40
  deref(deref(pp)).w = 2
  ## bind-mid: p2 := deref(pp) must infer ptr(mut Box)
  p2 := deref(pp)
  x := deref(p2).v                     ## 40
  ## READ through the nested deref
  y := deref(deref(pp)).w              ## 2
  return x + y                         ## 42
}
