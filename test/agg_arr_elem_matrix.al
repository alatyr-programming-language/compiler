## e2e (AGGREGATE ARRAY ELEMENT, the LOCAL array). Every access shape on a fixed array
## whose elements are a scalar-only STRUCT, each landing on a DISTINCT non-zero word offset so a
## dropped stride (element k read as word k) or a dropped field offset shows up as a wrong number:
##   1. constant-index field read at word 0, 1 and 2
##   2. runtime-index field read at word 2
##   3. whole-element COPY `e := xs[3]` into a struct local (all three words), read back by field
##   4. whole-element WRITE from a struct LITERAL at a RUNTIME index
##   5. whole-element WRITE from a struct VAR
##   6. element FIELD write `xs[i].c = 5` at a runtime index, non-zero offset
## The guards then assert the copy is INDEPENDENT of the later writes and that the neighbouring
## elements were never touched. 15 + 9 + 22 + 21 + 32 + 5 = 104.
Rec := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  mut xs : [Rec; 4] = [Rec(a = 1, b = 2, c = 3), Rec(a = 4, b = 5, c = 6), Rec(a = 7, b = 8, c = 9), Rec(a = 10, b = 11, c = 12)]
  mut r : u64 = 0
  ## 1. constant index, all three word offsets
  r = r + xs[1].a + xs[1].b + xs[1].c    ## 4 + 5 + 6 = 15
  ## 2. runtime index, word 2
  mut i : u64 = 2
  r = r + xs[i].c                        ## +9 = 24
  ## 3. whole-element copy into a struct local
  e := xs[3]
  r = r + e.a + e.c                      ## +10 +12 = 46
  ## 4. element write from a struct LITERAL, runtime index
  xs[i] = Rec(a = 20, b = 21, c = 22)
  r = r + xs[2].b                        ## +21 = 67
  ## 5. element write from a struct VAR
  q := Rec(a = 30, b = 31, c = 32)
  xs[0] = q
  r = r + xs[0].c                        ## +32 = 99
  ## 6. element FIELD write, runtime index, word 2
  xs[i].c = 5
  r = r + xs[2].c                        ## +5 = 104
  ## the copy is independent of the later element writes
  if e.b != 11 { return 1 }
  ## neighbours untouched by any of the writes
  if xs[1].a != 4 { return 2 }
  if xs[3].c != 12 { return 3 }
  ## the literal write landed on word 0 too (not only the word we read back)
  if xs[2].a != 20 { return 4 }
  r
}
