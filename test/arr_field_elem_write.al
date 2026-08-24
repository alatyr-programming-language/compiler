## Types §9.4 — inner-index WRITE into an ARRAY FIELD of an array-of-struct element `xs[i].arr[j] = v`
## (the store dual of the `arr_field_elem_read` READ). The `pad` field forces a non-zero field offset
## so a mis-composed (element base + field offset + inner index) store address is exposed. Was a SILENT
## DROP: the parser did not recognize `xs[i].arr[j] =` as a statement (the `ident [` head), so the line
## became a trailing-return expression and the write vanished. Writes across both elements + indices,
## then reads the writes back AND the untouched neighbours. 7 + 11 + 10 + 30 + 50 + 8 = 116 = success.
S := struct { pad : u64, arr : [u64; 3] }
main := fn() -> u64 {
  mut xs : [S; 2]
  xs[0] = S(pad = 9, arr = [10, 20, 30])
  xs[1] = S(pad = 8, arr = [40, 50, 60])
  xs[0].arr[1] = 7                       ## array-field element write (was 20)
  xs[1].arr[2] = 11                      ## on the OTHER element, a DIFFERENT index (was 60)
  u64(xs[0].arr[1]                       ## 7  (round-trip of write 1)
    + xs[1].arr[2]                       ## 11 (round-trip of write 2)
    + xs[0].arr[0]                       ## 10 (neighbour element, unchanged)
    + xs[0].arr[2]                       ## 30 (neighbour element, unchanged)
    + xs[1].arr[1]                       ## 50 (neighbour element, unchanged)
    + xs[1].pad)                         ## 8  (neighbour field, unchanged)
}
