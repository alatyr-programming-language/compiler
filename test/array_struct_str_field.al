## e2e (§4 layout — a `str` FIELD of an ARRAY-of-STRUCT element, `xs : [Kv; N]` with `key : str`).
## Compound of the a[i].f element-field read and the str-field 2-word layout: `xs[i].key` (a str value
## for `str_eq`, via `emit_str_pair`'s `str_field_arr_elem` case) and `xs[i].key.len` (`.ptr`/`.len` on
## a str field of an array element, via the Field arm) both address the element field and the word past
## it. A static keyword→code table is the motivating pattern. `src/`+`lib/` arrays-of-struct use scalar/
## span fields (never a `str` field), so this stays fixpoint-neutral.
Kv := struct { key : str, n : u64 }

lookup := fn(w : str) -> u64 {
  tab : [Kv; 3] = [Kv(key = "fn", n = 1), Kv(key = "let", n = 2), Kv(key = "return", n = 3)]
  mut r : u64 = 0
  mut i : usize = 0
  while i < 3 {
    if str_eq(tab[i].key, w) { r = tab[i].n }   ## str VALUE field of an array element
    i = i + 1
  }
  r
}

main := fn() -> u64 {
  a := lookup("return")                ## 3
  xs : [Kv; 2] = [Kv(key = "x", n = 10), Kv(key = "yz", n = 20)]
  b := xs[1].key.len + xs[1].n         ## "yz".len(2) + 20 = 22 (indexed str-field .len)
  c := xs[0].n                         ## 10
  d := xs[0].key.len                   ## "x".len = 1
  ## expected: 3 + 22 + 10 + 1 + 6 = 42
  a + b + c + d + 6
}
