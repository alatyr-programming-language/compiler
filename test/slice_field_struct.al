## e2e (Types §9.4 — a 2-word `{ptr, len}` VIEW as a struct FIELD). `View(T)` is the `Slice(T)` shape
## (`lib/base/slice.al`: `struct { ptr : ptr(T), len : usize }` — a library pair, not a primitive),
## declared here so the fixture needs no prelude injection. A field of that type is TWO words, and a
## range-slice value (`xs[lo..hi]`) / a slice VAR is neither a `StructLit` nor an `ArrayLit` and reports
## no aggregate slot kind — so the struct-literal store fell through to `emit_array_assign`, whose
## `_ => {}` stored NOTHING: `b.v.len` read 0 while the FOLLOWING scalar field still read correctly, a
## SILENT MISCOMPILE that silently truncates every `for`/bounds use built on the view.
## Locks three shapes against each other:
##   a = SB(v = xs[0..4], …)  — the 2-word field from a range-slice EXPR
##   b = SB(v = s, …)         — the 2-word field from a slice VAR
##   c = b.v                  — the 2-word field extracted into a LOCAL (both words, not just word 0)
##   byref(b)                 — the SAME extract through a BY-REFERENCE struct PARAM, which made the
##                              COMPILER trap: a bare `ud2` SIGILL (exit 132) with no diagnostic,
##                              because the copy read the POINTER slot as if it were the struct's own
##                              frame words instead of dereferencing it (pointee words ASCEND at +k*8)
## and reads the scalar field `n` of each so a mis-sized field (which would shift `n`) also shows up.
## Values: (4 + 5) + (3 + 6) + 3 + (3 + 6) = 9 + 9 + 3 + 9 = 30.
## NB the result MUST stay < 126 (the WASM sweep's WASI `proc_exit` only accepts [0,126)).
View := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }
SB := struct { v : View(u64), n : u64 }

byref := fn(x : SB) -> u64 {
  w := x.v                          ## a 2-word field of a BY-REFERENCE struct param → a local
  return u64(w.len) + x.n
}

main := fn() -> u64 {
  xs := [1, 2, 3, 4]
  s := xs[1..4]                     ## a slice VAR of length 3
  a := SB(v = xs[0..4], n = 5)      ## field ← a range-slice EXPR (length 4)
  b := SB(v = s, n = 6)             ## field ← a slice VAR (length 3)
  c := b.v                          ## the 2-word field bound to a local
  return (u64(a.v.len) + a.n) + (u64(b.v.len) + b.n) + u64(c.len) + byref(b)
}
