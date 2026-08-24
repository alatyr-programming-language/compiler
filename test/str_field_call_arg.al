## e2e (Types §7 — a `[T]`/`str` view is its two-word {ptr, len} pair WHEREVER it appears, so a view
## FIELD is a 2-word sub-aggregate inside its struct and a call argument must pass that pair's
## ADDRESS). Before the fix `emit_arg` classified arguments by SHAPE and had no arm for a view FIELD:
## it fell to the scalar path and pushed the field's FIRST word (the data pointer) as if it were the
## by-reference block pointer, so `io::print(p.name)` printed NOTHING and `len(p.name)` returned
## garbage — silent wrong values (I11), in statement AND value position.
##
## CONTENT is checked with `str_eq`, never a length: the four names have lengths 5/2/7/5, and the
## `"Alicia"` probe has the SAME length as a wrong-but-plausible answer, so a wrong length or a
## wrong pointer cannot pass. Shapes covered: a field of a struct LOCAL, a field of a BY-REFERENCE
## struct PARAM, a NESTED field (`q.inner.name`), a field at a NON-ZERO word offset (`q.tag` sits
## past a 3-word struct), and a `Slice(u8)` view field. The last line is the POSITIVE CONTROL: a
## plain `str` LOCAL argument, the path that always worked, so the fix cannot regress it. 42.
P := struct { name : str, n : u64 }
Q := struct { inner : P, tag : str }
R := struct { bs : Slice(u8), n : u64 }

eqs := fn(s : str, want : str) -> u64 {
  if str_eq(s, want) { return 1 }
  0
}
blen := fn(b : Slice(u8)) -> u64 { return b.len }
byref := fn(p : P) -> u64 { return eqs(p.name, "Alice") }

main := fn() -> u64 {
  p := P(name = "Alice", n = 7)
  q := Q(inner = P(name = "Bo", n = 1), tag = "Carolyn")
  r := R(bs = bytes("Alice"), n = 3)
  s : str = "plain"
  mut k : u64 = 0
  k += eqs(p.name, "Alice")            ## field of a struct LOCAL
  k += byref(p)                        ## field of a BY-REFERENCE struct PARAM
  k += eqs(q.inner.name, "Bo")         ## NESTED view field
  k += eqs(q.tag, "Carolyn")           ## view field at a NON-ZERO word offset
  k += eqs(p.name, "Alicia")           ## must be 0 — same-ish text, different content
  if blen(r.bs) == 5 { k += 1 }        ## a `Slice(u8)` view field
  k += eqs(s, "plain")                 ## POSITIVE CONTROL — a plain `str` local
  if k == 6 { return 42 }
  k
}
