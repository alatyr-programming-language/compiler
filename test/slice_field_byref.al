## e2e (Types §9.4 — a 2-word `{ptr, len}` VIEW FIELD read DIRECTLY on a BY-REFERENCE struct param).
## A wide struct param is passed BY REFERENCE, so `x.v.len` must load the caller's word-0 pointer and
## read the field at its ASCENDING pointee offset. `str_field_place` — the resolver that composes
## exactly that — accepted only a field spelled `str`, so a `v : Slice(T)` field matched no arm and
## fell to `field_slot`, whose `Var` arm computes `ent.off - fi` off a slot that holds a POINTER, not
## the inline struct: `x.v.len` read a garbage frame word (in practice a folded 0) — a SILENT
## MISCOMPILE whose only working spelling was to extract the field first (`w := x.v; w.len`).
## Locks the DIRECT reads through a by-ref param — `.len` with the pair field FIRST and LAST, and
## `x.v[i]` (whose element address must likewise come from the pointee, not the frame).
## Value: 4 + 2 + 10 + 40 = 56 (< 126 — the WASM sweep's WASI `proc_exit` bound).
SA := struct { v : Slice(u64), n : u64 }
SB := struct { n : u64, v : Slice(u64) }

lenof := fn(x : SA) -> u64 { return u64(x.v.len) }        ## was 0
lenof2 := fn(x : SB) -> u64 { return u64(x.v.len) }       ## the pair field LAST
elem := fn(x : SA, i : usize) -> u64 { return u64(x.v[i]) }

main := fn() -> u64 {
  xs := [10, 20, 30, 40]
  a := SA(v = xs[0..4], n = 7)
  b := SB(n = 8, v = xs[1..3])
  if lenof(a) != 4 { return 1 }
  if lenof2(b) != 2 { return 2 }
  if elem(a, 2) != 30 { return 3 }
  if a.n != 7 { return 4 }
  if b.n != 8 { return 5 }
  return lenof(a) + lenof2(b) + elem(a, 0) + elem(a, 3)
}
