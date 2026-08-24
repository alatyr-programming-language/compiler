## Types §9.4 — DEEP fixed-array element nested-field WRITE `xs[i].b.c.cx = v` (depth-3 field chain
## off an array-of-struct element; the store dual of the `deep_arr_elem_field` READ). `pa`/`pb`
## leading fields force non-zero word offsets so a mis-composed store address is exposed. Was a
## SILENT DROP: the parser did not recognize `xs[i].f1.f2… =` as a statement (the `ident [` head), so
## the line became a trailing-return expression and the write vanished. Writes the deep leaf on BOTH
## elements, then reads the writes back AND every neighbour field to confirm none was clobbered.
## 7 + 20 + 30 + 3 + 11 + 9 = 80 = success (any clobber shifts the sum).
C := struct { cx : u64, cy : u64 }
B := struct { pb : u64, c : C }
A := struct { pa : u64, b : B, tail : u64 }
main := fn() -> u64 {
  mut xs : [A; 2]
  xs[0] = A(pa = 11, b = B(pb = 22, c = C(cx = 5, cy = 30)), tail = 7)
  xs[1] = A(pa = 1, b = B(pb = 2, c = C(cx = 3, cy = 4)), tail = 9)
  xs[0].b.c.cx = 7                       ## deep write (was 5)
  xs[1].b.c.cy = 20                      ## deep write on the OTHER element (was 4)
  u64(xs[0].b.c.cx                       ## 7  (round-trip of write 1)
    + xs[1].b.c.cy                       ## 20 (round-trip of write 2)
    + xs[0].b.c.cy                       ## 30 (neighbour leaf, unchanged)
    + xs[1].b.c.cx                       ## 3  (neighbour leaf, unchanged)
    + xs[0].pa                           ## 11 (neighbour outer field, unchanged)
    + xs[1].tail)                        ## 9  (neighbour outer field, unchanged)
}
