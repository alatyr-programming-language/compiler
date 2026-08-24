## e2e (§4 layout — a `str` ARRAY `[str; N]`, indexed access). Each element is a 2-word `{ptr, len}`
## (Memory §3.5), so `arr_elem_info` sizes str elements at stride 2; indexed access must materialize
## the element's `{ptr, len}` at `base + i*stride`. Exercises: `xs[i]` as a str VALUE (passed to
## `str_eq`, via `emit_str_pair`'s Index case) and `xs[i].len` (the `.ptr`/`.len` on an indexed str
## element, via the Field-arm Index case). `src/`+`lib/` use `contains(str, table, w)` over span
## tables, not `[str; N]` indexed `.len`, so this stays fixpoint-neutral.
kw := fn(w : str) -> u64 {
  tab : [str; 3] = ["fn", "let", "return"]
  mut r : u64 = 0
  mut i : usize = 0
  while i < 3 {
    if str_eq(tab[i], w) { r = i + 1 }   ## str VALUE read via str_eq
    i = i + 1
  }
  r
}

main := fn() -> u64 {
  a := kw("return")                       ## 3 (index 2 + 1)
  b := kw("nope")                         ## 0
  xs : [str; 2] = ["hi", "world"]
  c := xs[1].len                          ## "world".len = 5 (indexed str-element .len)
  d := xs[0].len                          ## "hi".len = 2
  a + b + c + d + 32                      ## 3 + 0 + 5 + 2 + 32 = 42
}
