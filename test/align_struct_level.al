## §8 struct-level `@align(N) struct { … }` — the STRUCT's own alignment lever (spec Types §8: raise
## alignment above natural; §6.1: the struct's size rounds UP to its alignment). Distinct from the
## field-level `@align` (which raises a field's offset inside a @packed byte layout): this raises the
## WHOLE struct's alignment and rounds its size up. Here V is a plain (word-model) struct of three u64
## fields — natural size 3 words = 24 bytes, natural alignment 8 — carrying `@align(16)`:
##   align(V) == 16  (raised above the natural 8)
##   size(V)  == 32  (24 rounded up to the next multiple of 16)
## A silently-ignored struct-level @align would report align 8 / size 24 and fail these checks. The field
## reads prove the ordinary word-sized layout still works (a struct-level lever changes size/align only,
## not the field offsets). Returns 42.
V := @align(16) struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  v := V(a = 10, b = 20, c = 12)
  if align(V) != 16 { return 1 }        ## raised above the natural 8
  if size(V) != 32 { return 2 }         ## 3 words = 24, rounded up to the 16-multiple 32
  if v.a != 10 { return 3 }
  if v.b != 20 { return 4 }
  if v.c != 12 { return 5 }
  return v.a + v.b + v.c                 ## 42
}
