## Struct-literal field VALUE that is an AGGREGATE bound var (not an inline construct). An inline
## aggregate field value (`p = Pt(x=3, y=2)`) already emitted a full multi-word write into the
## field slot; a BOUND-VAR aggregate value (`p = q`) dropped the copy — the field read word 0 as 0
## (silent-wrong-data "generic-struct-LITERAL EMIT corner", but the defect is
## general to any struct literal). Covers non-generic + generic (1- and 2-word field) shapes. → 42.

Pt    := struct { x : usize, y : usize }
Box   := struct { p : Pt, tag : usize }
Slice := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }
Wrap  := fn(T : type) -> type { return struct { inner : Slice(T), tag : usize } }

main := fn() -> u64 {
  ## (1) non-generic: a 2-word aggregate bound var as a field value.
  q := Pt(x = 3, y = 2)
  b := Box(p = q, tag = 10)
  a := u64(b.p.x) + u64(b.p.y) + u64(b.tag)      ## 3 + 2 + 10 = 15

  ## (2) generic struct: a Slice(u8) bound var as a generic-struct field value.
  s : Slice(u8) = Slice(u8)(ptr = "xy".ptr, len = 5)
  w := Wrap(u8)(inner = s, tag = 22)
  c := u64(w.inner.len) + u64(w.tag)             ## 5 + 22 = 27

  return a + c                                    ## 15 + 27 = 42
}
