## e2e (issue #495 — a SILENT WRONG VALUE, the GLOBAL twin of #394). The BYTE at index `j` of the
## `str` ELEMENT `k` of a MODULE-LEVEL `[str; N]` global: `G[k][j]`. Types §7 makes each element a
## two-word `{ptr, len}` view and appendix 160 §3.5 makes `str` a `[u8]`, so the read must resolve
## element `k`'s pair at the 2-word element stride and then load ONE byte at `ptr + j`.
##
## FAILURE-FIRST (measured on the parent, fbeabe4). Two separate defects, both silent:
##   1. The `.data`/`.rodata` IMAGE. A str element has no scalar init value, so every element imaged
##      as ONE `.quad 0` — a null pointer, no length word, and a 1-word stride. `["abc", "XYZ"]`
##      became `.quad 0` / `.quad 0`, so NO addressing could have answered correctly.
##   2. The READ. The base `Index(G, k)` is not a `Var` and a global has no frame slot, so every
##      name-keyed str-element arm declined it: `G[k][j]` fell to the untyped `emit_index_addr` tail,
##      which answered frame SLOT 0 (the issue measured **5** where **90** was due — a real string
##      byte, not obvious garbage, the #421 plausible-number hazard) until #425 made that refusal
##      loud, and the element as a str VALUE fell to `emit_str_pair`'s EMPTY-pair default, which made
##      `str_eq(G[k], "…")` unconditionally FALSE and `bytes(G[k])[j]` trap on a zero length.
## On the parent this fixture does not build at all — #425's tail refusal names `GZ[1][2]`, so the row
## FAILS at compile/link. The silent number the issue reports was measured directly on the last tree
## before that refusal (85f99bd, pre-#425): `G[1][2]` on this very global answered **5** while the
## LOCAL spelling `arr[1][2]` over the same `["abc", "XYZ"]` answered **90**. So the local root really
## is correct and this is a global-root defect, not a shared one. The other three backends TRAP on the
## whole shape (a133 / rv133 / wasm134) before and after, exactly as they do for the LOCAL spelling, so
## none is turned from a trap into a wrong value.
##
## No alias-encoded codes (issue #386): every DISTINGUISHABLE wrong answer has its OWN code — the
## issue's own plausible number 5, a zero/empty view, the byte at the same offset of a DIFFERENT
## element, the byte at a DIFFERENT offset of the CORRECT element, the element's LENGTH (the
## `{ptr, len}` words taken in the wrong order), and a catch-all for any other byte.
##
## The strings have DIFFERENT LENGTHS (3/3, 7/3/10, 5/8) and every inner index is chosen so the
## offset lands on a DIFFERENT byte in every other element of the same array — `GC[0][5]` is even
## PAST the end of `GC[1]` — so an outer index that is ignored, off by one, or mis-strided cannot
## pass by coincidence. Element bytes are pairwise distinct inside each element and disjoint between
## the arrays, so no read can be satisfied by the wrong array either.
##
## Both root visibilities are covered, because visibility of the root is what the local/global split
## turns on: `GZ`/`GC` are CONST (non-`mut`) array globals and `GM` is a `mut` one. `src/` and `lib/`
## declare no module-level array global at all, so this stays fixpoint-neutral.

## the issue's own data — `GZ[1][2]` is 'Z' = 90, and the parent answered 5
GZ := ["abc", "XYZ"]
## unequal lengths 7 / 3 / 10; every byte distinct inside its element
GC := ["ABCDEFG", "uvw", "0123456789"]
## a MUTABLE global with DISJOINT contents, lengths 5 / 8
mut GM : [str; 2] = ["hijkl", "MNOPQRST"]

## the LOCAL spelling, fixed upstream by #409/#415 — the control that must be green on BOTH sides
local_elem_byte := fn() -> u64 {
  arr : [str; 3] = ["ABCDEFG", "uvw", "0123456789"]
  u64(arr[0][5])
}

## a frame LOCAL that SHADOWS the global name `GC` must keep the LOCAL path: the global recognizer
## resolves its root through the module-global rules, which return nothing when a slot owns the name.
shadowed := fn() -> u64 {
  GC : [str; 2] = ["wxyz", "5678"]
  u64(GC[1][1])                            ## the LOCAL's '6' = 54, never the global's 'v' = 118
}

main := fn() -> u64 {
  ## ---- the issue's own reproducer: a non-`mut` global, `GZ[1][2]` = 'Z' = 90 ----
  a := u64(GZ[1][2])
  if a == 5   { return 1 }                 ## the plausible frame-slot-0 word the issue measured
  if a == 0   { return 2 }                 ## a zero / an empty {0, 0} view
  if a == 99  { return 3 }                 ## 'c' — the same offset of a DIFFERENT element
  if a == 88  { return 4 }                 ## 'X' — a DIFFERENT offset of the CORRECT element
  if a == 3   { return 5 }                 ## the element's LENGTH, not its byte
  if a != 90  { return 6 }                 ## any other wrong byte

  ## ---- unequal lengths: offset 5 is valid in GC[0] and PAST THE END of GC[1] ----
  b := u64(GC[0][5])                       ## 'F' = 70
  if b == 0   { return 7 }
  if b == 7   { return 8 }                 ## element 0's LENGTH
  if b == 53  { return 9 }                 ## '5' — offset 5 of element 2
  if b == 65  { return 10 }                ## 'A' — offset 0 of the correct element (offset dropped)
  if b != 70  { return 11 }

  ## ---- the LAST element and its LAST byte: only a correct 2-word stride reaches it ----
  c := u64(GC[2][9])                       ## '9' = 57
  if c == 0   { return 12 }
  if c == 10  { return 13 }                ## element 2's LENGTH
  if c == 48  { return 14 }                ## '0' — offset 0 of the correct element
  if c != 57  { return 15 }

  ## ---- a MUTABLE global root, disjoint contents ----
  d := u64(GM[1][3])                       ## 'P' = 80
  if d == 0   { return 16 }
  if d == 8   { return 17 }                ## element 1's LENGTH
  if d == 107 { return 18 }                ## 'k' — offset 3 of element 0 (the wrong element)
  if d == 77  { return 19 }                ## 'M' — offset 0 of the correct element
  if d != 80  { return 20 }
  e := u64(GM[0][0])                       ## 'h' = 104 — element 0, offset 0
  if e == 0   { return 21 }
  if e == 5   { return 22 }                ## element 0's LENGTH
  if e == 77  { return 23 }                ## 'M' — element 1's first byte
  if e != 104 { return 24 }

  ## ---- NON-CONSTANT outer and inner indices ----
  mut k : u64 = 1
  mut j : u64 = 2
  f := u64(GC[k][j])                       ## "uvw"[2] = 'w' = 119
  if f == 0   { return 25 }
  if f == 67  { return 26 }                ## 'C' — element 0 at the same offset
  if f == 117 { return 27 }                ## 'u' — the correct element at offset 0
  if f != 119 { return 28 }
  k = 2
  j = 7
  g := u64(GC[k][j])                       ## "0123456789"[7] = '7' = 55
  if g != 55  { return 29 }

  ## ---- the element as a whole str VALUE: the same recognizer, the pair path ----
  ## `str_eq(G[k], "…")` was unconditionally FALSE on the parent (the empty-pair default)
  if not str_eq(GC[1], "uvw")      { return 30 }
  if str_eq(GC[1], "ABCDEFG")      { return 31 }   ## and it must not match a DIFFERENT element
  if not str_eq(GM[1], "MNOPQRST") { return 32 }
  ## `bytes(G[k])[j]` TRAPPED on the parent (a zero length); it must now name the SAME byte as the
  ## nested spelling — two commands claiming the same result have to agree
  if u64(bytes(GC[2])[9]) != c     { return 33 }
  if u64(bytes(GM[1])[3]) != d     { return 34 }

  ## ---- controls that must be green on BOTH sides ----
  if local_elem_byte() != 70       { return 35 }   ## the LOCAL root, #409/#415
  if shadowed() != 54              { return 36 }   ## a local shadowing the global name

  ## ---- CG-7: an `unchecked` scope drops the bounds check and keeps the SAME byte ----
  if u64(unchecked GC[2][9]) != 57 { return 37 }
  if u64(unchecked GM[0][0]) != 104 { return 38 }

  42
}
