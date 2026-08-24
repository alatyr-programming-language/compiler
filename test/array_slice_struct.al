## typed-slice: slicing a STRUCT-element array `[Pt; N]` yields a typed slice whose
## elements are structs — `s[i].field` reads the field through the slice pointer (element stride =
## the struct's word count, element type span carried so field resolution works).
Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  ps := [Pt(x = 20, y = 1), Pt(x = 20, y = 1), Pt(x = 5, y = 5)]
  s := ps[0..2]                                ## {Pt(20,1), Pt(20,1)}
  return s[0].x + s[0].y + s[1].x + s[1].y     ## 20 + 1 + 20 + 1 = 42
}
