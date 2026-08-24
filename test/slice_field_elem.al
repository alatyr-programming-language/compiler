## e2e (Types §9.4 — INDEXING a 2-word `{ptr, len}` VIEW FIELD). A `Slice(T)` / `str` FIELD is a
## POINTER + a length, NOT an inline `[T; N]` array laid out in the struct's own words, so element `i`
## sits at `load(field word 0) + i*stride` — not at `field word 0 + i*8`. `emit_index_addr`'s
## struct-array-FIELD branch (`field_index_base`, which reports `is_fld` for EVERY resolvable field)
## applied the INLINE-array math to it and read the {ptr, len} words themselves as elements: `st.v[1]`
## and `st.name[1]` returned the LENGTH — a SILENT MISCOMPILE, while `.len` on the same field was
## correct, so the two reads disagreed. A second, independent silent fault fed it: the struct-literal
## FIELD STORE materialized `xs[0..3]` with the *str* (byte-view) pair reading, storing `xs`'s first
## ELEMENT (10) as the "data pointer" instead of element 0's ADDRESS + `lo*stride*8`.
## Locks, against each other:
##   a.v[i]      — the pair field indexed, filled from a range-slice EXPR (field FIRST)
##   b.v[i]      — the same, filled from a slice VAR, with the pair field LAST
##   c[i]        — the documented `c := a.v` extract-to-a-local workaround (was ALSO wrong)
##   g.xs[i]     — an INLINE `[u64; 3]` field: the path that must stay BYTE-IDENTICAL (regression)
##   h.name[i]   — a `str` field: the BYTE dual (`str` IS `[u8]`, appendix 160 §3.5)
## and reads each struct's scalar field so a mis-sized pair field (which would shift it) also shows up.
## Value: 10 + 30 + 20 + 1 + 5 = 66. NB it MUST stay < 126 (the WASM sweep's WASI `proc_exit`).
S := struct { v : Slice(u64), n : u64 }
T := struct { n : u64, v : Slice(u64) }
A := struct { xs : [u64; 3], n : u64 }
N := struct { name : str, n : u64 }

main := fn() -> u64 {
  xs := [10, 20, 30]
  s := xs[0..3]
  a := S(v = xs[0..3], n = 1)         ## pair field FIRST, from a range-slice EXPR
  b := T(n = 2, v = s)                ## pair field LAST, from a slice VAR
  c := a.v                            ## the pair field extracted into a LOCAL
  g := A(xs = [1, 2, 3], n = 4)       ## an INLINE [T; N] field — must not move
  h := N(name = "hello", n = 5)
  if a.v[0] != 10 { return 1 }        ## was the stored "pointer" word (10 read as an address)
  if a.v[1] != 20 { return 2 }
  if a.v[2] != 30 { return 3 }
  if a.v.len != 3 { return 4 }
  if a.n != 1 { return 5 }
  if b.v[1] != 20 { return 6 }
  if b.n != 2 { return 7 }
  if c[2] != 30 { return 8 }
  if g.xs[2] != 3 { return 9 }        ## the inline-array-field path (regression guard)
  if g.n != 4 { return 10 }
  if h.name[1] != 101 { return 11 }   ## 'e' — a str field indexes BYTES; was the len word (5)
  if h.n != 5 { return 12 }
  return u64(a.v[0]) + u64(b.v[2]) + u64(c[1]) + u64(g.xs[0]) + h.n
}
