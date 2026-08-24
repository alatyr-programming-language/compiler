## e2e — AGGREGATE-ELEMENT array GLOBAL. A `mut TAB := [Pt(…), …]` global has no frame slot: its
## elements live at a FIXED base in the module's constant image, laid out flattened at `stride` words
## each. Covers the field read at a runtime index (`TAB[i].y`), the whole-element COPY out of the
## global (`e := TAB[2]`, which must snapshot the words — a later write to TAB[2] must not show
## through `e`), and the whole-element WRITE into the global (`TAB[2] = Pt(…)`). Distinct non-zero
## field values at non-zero element offsets, plus untouched-neighbour checks. Returns 71.
Pt := struct { x : u64, y : u64 }
mut TAB := [Pt(x = 3, y = 4), Pt(x = 5, y = 6), Pt(x = 7, y = 8)]
main := fn() -> u64 {
  mut i := 1
  mut r : u64 = 0
  r = r + TAB[i].y             ## 6   element 1's word-1 field, runtime index
  e := TAB[2]                  ## whole-element COPY out of the global: (7, 8)
  TAB[2] = Pt(x = 40, y = 50)  ## whole-element WRITE into the global
  r = r + e.x + e.y            ## +15 = 21   the copy kept the OLD words
  r = r + TAB[2].y             ## +50 = 71   the write landed at word 1 of element 2
  if TAB[0].x != 3 { return 1 }
  if TAB[1].y != 6 { return 2 }
  if TAB[2].x != 40 { return 3 }
  r                             ## 71
}
