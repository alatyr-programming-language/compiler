## e2e (§4 layout — an ARRAY of TUPLES `[(A, B); N]`). A tuple is an N-word aggregate (built as an
## ArrayLit), so a tuple ELEMENT occupies its component count in words: `arr_elem_info` gives it
## `eek 5` / stride = components, the construction stores each element's components recursively
## (`emit_array_assign`), and `xs[i].N` (parsed `Index(Index(xs, i), N)`) reads component N at the
## strided element base via `emit_index_addr`. `src/`+`lib/` use arrays of scalars/structs, not
## arrays of tuples, so this stays fixpoint-neutral.
main := fn() -> u64 {
  xs : [(u64, u64); 3] = [(40, 2), (10, 20), (1, 1)]
  a := xs[0].0 + xs[0].1        ## 40 + 2 = 42 (element 0's components)
  b := xs[1].0 + xs[1].1        ## 10 + 20 = 30 (element 1 — strided element base)
  c := xs[2].0 + xs[2].1        ## 1 + 1 = 2
  if a == 42 and b == 30 and c == 2 { return 42 }
  1
}
