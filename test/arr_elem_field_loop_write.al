## e2e — AGGREGATE ARRAY ELEMENT at a LOOP-driven RUNTIME index, on a WIDE (4-word) element struct:
## every iteration reads two fields of element `i` (`xs[i].a`, `xs[i].d`) and writes a third
## (`xs[i].c = …`), so a stride slip or a field-offset slip lands on a different, distinct value and
## changes the answer. Then a whole-element COPY (`e := xs[2]`) must own its words — the later
## whole-element WRITE `xs[2] = Q(…)` must not show through `e`. Widths matter: 4 words per element is
## wider than every other fixture in this family, so a 2/3-word stride assumption is caught here.
##   after the loop: xs[0].c = 1+4 = 5, xs[1].c = 5+8 = 13, xs[2].c = 9+12 = 21
##   e = (9, 10, 21, 12); xs[2] = (50, 51, 52, 53)
##   5 + 13 + 21 + 51 = 90
Q := struct { a : u64, b : u64, c : u64, d : u64 }
main := fn() -> u64 {
  mut xs : [Q; 3] = [Q(a = 1, b = 2, c = 3, d = 4), Q(a = 5, b = 6, c = 7, d = 8), Q(a = 9, b = 10, c = 11, d = 12)]
  mut i := 0
  while i < 3 {
    xs[i].c = xs[i].a + xs[i].d
    i = i + 1
  }
  e := xs[2]                             ## whole-element COPY of (9, 10, 21, 12)
  xs[2] = Q(a = 50, b = 51, c = 52, d = 53)
  mut r : u64 = 0
  r = r + xs[0].c                        ## 5
  r = r + xs[1].c                        ## +13 = 18
  r = r + e.c                            ## +21 = 39   the copy kept the pre-write word 2
  r = r + xs[2].b                        ## +51 = 90   the literal write landed (word 1)
  if e.a != 9 { return 1 }               ## the copy is independent of the later element write
  if e.d != 12 { return 2 }              ## its last word too
  if xs[0].a != 1 { return 3 }           ## the loop wrote ONLY word 2 of element 0
  if xs[1].d != 8 { return 4 }           ## and only word 2 of element 1
  if xs[2].d != 53 { return 5 }          ## the literal write's last word landed
  r                                       ## 90
}
