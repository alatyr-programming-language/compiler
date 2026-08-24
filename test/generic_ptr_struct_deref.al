## e2e (generic-aggregate frontier: `deref(ptr(V))` for a type-param `V` monomorphized to a MULTI-WORD
## struct). In a generic fn taking `V : type` + `ptr(mut V)`/`ptr(V)`, three shapes previously lost
## word 1+ because `V` is concrete only AFTER monomorphization, so a `ptr(V)` param/pointee never
## resolved to a struct and each deref moved ONE word:
##   PARAM-STORE  `deref(vslot) = value`  (value : V)          — already worked (value's slot is ek 2)
##   LOAD         `x := deref(vp)`         (vp : ptr(V))        — fixed: `ptr(V)` param now binds ek 7
##                                                                via the instance Subst → whole copy
##   STORE        `deref(vd) = deref(vs)`  (vd,vs : ptr(mut V)) — fixed: ek-7 dest + Deref source →
##                                                                pointee→pointee multi-word copy
## Rec is 2 words (a, b). If word 1 were dropped, `.b` would read 0 and the sum would be 40, not 42.
Rec := struct { a : i64, b : i64 }

gstore := fn(V : type, vslot : ptr(mut V), value : V) { deref(vslot) = value }
gcopy := fn(V : type, vd : ptr(mut V), vs : ptr(mut V)) { deref(vd) = deref(vs) }
gload := fn(V : type, vp : ptr(V), vd : ptr(mut V)) {
  x := deref(vp)
  deref(vd) = x
}

main := fn() -> i64 {
  mut src := Rec(a = 40, b = 2)
  mut d1 := Rec(a = 0, b = 0)
  gstore(Rec, ptr(mut d1), src)              ## PARAM-STORE: d1 = {40, 2}
  mut d2 := Rec(a = 0, b = 0)
  gcopy(Rec, ptr(mut d2), ptr(mut d1))       ## STORE:       d2 = deref(&d1)
  mut d3 := Rec(a = 0, b = 0)
  gload(Rec, ptr(mut d1), ptr(mut d3))       ## LOAD then store: d3 = deref(&d1)
  if d1.a != 40 { return 1 }
  if d1.b != 2 { return 2 }
  if d2.a != 40 { return 3 }
  if d2.b != 2 { return 4 }
  if d3.a != 40 { return 5 }
  if d3.b != 2 { return 6 }
  d1.b + d2.b + d3.a - d2.a + d3.b + 36      ## 2 + 2 + 40 - 40 + 2 + 36 = 42
}
