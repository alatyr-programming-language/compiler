## e2e — AGGREGATE-ELEMENT array LOCAL, read AND write, in one program: the element of a `[Rec; N]`
## spans `stride` words, so its VALUE is a base address, not a word load. Covers the four shapes:
##   * `arr[i].c`  — field read at a RUNTIME index (word 2 of element 2, so a stride or field-offset
##                   slip lands on a different, distinct value)
##   * `e := arr[1]` — whole-element COPY: `e` must own its words, so a later write to arr[1] must
##                     NOT show through `e` (aliasing the element would move `e.a`/`e.b`/`e.c`)
##   * `arr[1] = q` — whole-element WRITE from a struct VAR
##   * `arr[3] = Rec(…)` — whole-element WRITE from a struct LITERAL
## Every field holds a distinct non-zero value at a non-zero offset, and the untouched neighbours are
## re-checked, so a dropped or misordered word changes the answer. Returns 119.
Rec := struct { a : u64, b : u64, c : u64 }
main := fn() -> u64 {
  mut arr : [Rec; 4] = [Rec(a = 1, b = 2, c = 3), Rec(a = 4, b = 5, c = 6), Rec(a = 7, b = 8, c = 9), Rec(a = 10, b = 11, c = 12)]
  mut i := 2
  mut r : u64 = 0
  r = r + arr[i].c                        ## 9   word-2 field of element 2, runtime index
  e := arr[1]                             ## whole-element COPY of (4, 5, 6)
  q := Rec(a = 20, b = 30, c = 40)
  arr[1] = q                              ## whole-element WRITE from a struct VAR, over the copied element
  arr[3] = Rec(a = 50, b = 60, c = 70)    ## whole-element WRITE from a struct LITERAL
  r = r + e.a + e.c                       ## +10 = 19   the copy kept the OLD words (4, 6)
  r = r + arr[1].b                        ## +30 = 49   the var write landed (word 1)
  r = r + arr[3].c                        ## +70 = 119  the literal write landed (word 2)
  if e.b != 5 { return 1 }                ## the copy is independent of the later element write
  if arr[0].a != 1 { return 2 }           ## neighbour element before both writes intact
  if arr[2].b != 8 { return 3 }           ## neighbour element between them intact
  if arr[3].a != 50 { return 4 }          ## the literal write's word 0 landed too
  r                                        ## 119
}
