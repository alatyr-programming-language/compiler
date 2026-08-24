## e2e (for-over-iterable over a struct/enum-ELEMENT array — `for p in <[Pt; N]>`). This SEGFAULTED:
## the iterable loop only handled scalar/float element arrays (element count in `snl`); a struct
## array keeps `snl` = the element type span, so it fell to the slice path and read garbage. Now the
## loop var is bound as the element aggregate (collect_slots), the element count `N` is recovered
## from the `[Pt; N]` annotation via local_type_span + parse_arr_len (the slot has no count for an
## aggregate array), the hidden index sits at `vslot+stride` (past the wide loop var), and each
## iteration COPIES the `stride`-word struct element into the loop var's slots. `p.x`/`p.y` read them.
Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  a : [Pt; 3] = [Pt(x = 10, y = 1), Pt(x = 20, y = 2), Pt(x = 8, y = 1)]
  mut s : u64 = 0
  for p in a { s = s + p.x + p.y }
  s                              ## 10+1 + 20+2 + 8+1 = 42
}
