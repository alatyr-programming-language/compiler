## e2e (§4 layout — an ARRAY FIELD inside a mutable-global struct, read AND write). An array field
## `[T; N]` occupies N words in the struct, so a scalar field after it shifts by N; the array field's
## `.data` cells are the element values (not one zero `.quad`). Element `i` sits at `LABEL +
## (field_word_offset(xs) + i)*8`. Exercises: element READ (`gg.xs[i]`), element WRITE (`gg.xs[i] =`),
## scalar-field READ/WRITE after the array (`gg.n`, at the shifted word offset), and the initial `.data`.
## `src/` uses spans + frame arrays, not array fields in globals, so this stays fixpoint-neutral.
G := struct { xs : [u64; 3], n : u64 }
mut gg := G(xs = [10, 20, 5], n = 3)

main := fn() -> u64 {
  ## initial reads: xs = {10,20,5}, n = 3
  mut r : u64 = gg.xs[0] + gg.xs[1] + gg.xs[2] + gg.n   ## 10+20+5+3 = 38
  ## writes: shift an element and the trailing scalar (word offset must clear the 3-word array)
  gg.xs[2] = 1                                          ## xs now {10,20,1}
  gg.n = 3                                              ## n unchanged
  r = r + gg.xs[2] + gg.n                               ## 38 + 1 + 3 = 42
  r
}
