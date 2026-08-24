## §4/§8: MIXED-KIND tuple PARAMETER field access. A tuple param whose components differ in width/kind
## (a scalar next to a wider struct) is bound by-reference with only its FIRST component as the element
## span, so `t.N.field` for a later, differently-typed component was fail-loud ("mixed-kind tuple PARAM
## field access not yet supported"). param_tuple_layout_collect now records the per-component layout
## (type + cumulative offset) for a non-uniform tuple param — the by-ref dual of the tuple-LOCAL path —
## so `t.1.x`/`t.1.y` resolve element 1's own struct type. sum((12, Pt(20,10))) = 12+20+10 = 42.
Pt := struct { x : u64, y : u64 }

sum := fn(t : (u64, Pt)) -> u64 {
  return t.0 + t.1.x + t.1.y
}

main := fn() -> u64 {
  p := (12, Pt(x = 20, y = 10))
  return sum(p)
}
