## e2e — whole-element read from a mutable STRUCT-array global (`e := ARR[i]`). The global has no frame
## slot, so index_value_layout resolves the element struct from the global's ArrayLit and emit_elem_copy_in
## copies its `stride` words from the global's `.data` (ASCENDING: base LABEL+i*stride*8, word k at +k*8)
## into the down-growing local `e`. Then `e.x`/`e.y` read the local. e = ARR[0] = {40,1}; 40+1+1 = 42.
Pt := struct { x : u64, y : u64 }
mut ARR := [Pt(x = 40, y = 1), Pt(x = 1, y = 0)]
main := fn() -> u64 {
  mut i := 0
  e := ARR[i]
  e.x + e.y + 1
}
