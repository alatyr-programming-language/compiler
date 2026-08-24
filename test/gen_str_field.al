## e2e (Types §9.4 — a `str` type-ARGUMENT filling a generic struct's type-PARAM field). `Box(str)`'s
## `v : T` is a 2-word `{ptr, len}` value, but its RAW declared span is `T`, so every `== "str"` probe
## on the raw span missed and the field fell to the array/scalar paths, which stored NOTHING (the
## construction) or pushed ONE word (the by-value return): `b.v.len` read 0 — a SILENT MISCOMPILE, on
## the construction AND on the return. The layout side (`struct_words` / `field_word_offset`) already
## substituted through `subst_field_ty`; only the STORE and the RETURN-register delivery did not.
## Locks three shapes against each other:
##   d = Box(str)(v = "hi", n = 7)   — a DIRECT generic instance, str LITERAL field
##   g = mkbox(str, "abc")           — a generic fn whose str PARAM fills the type-param field AND
##                                     whose `-> Box(T)` return carries it back by value
##   s = Box(u64)(v = 5, n = 7)      — the SCALAR type-arg control: its layout is one word per field
##                                     and must be completely unaffected
## Values: (2 + 7) + (3 + 7) + (5 + 7) = 9 + 10 + 12 = 31.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
Box := fn(T : type) -> type { return struct { v : T, n : u64 } }

mkbox := fn(T : type, x : T) -> Box(T) {
  return Box(T)(v = x, n = 7)
}

main := fn() -> u64 {
  d := Box(str)(v = "hi", n = 7)
  g := mkbox(str, "abc")
  s := Box(u64)(v = 5, n = 7)
  return (d.v.len + d.n) + (g.v.len + g.n) + (s.v + s.n)
}
