## build_reject — Stdlib §2.6: a bare comparison over a WHOLE multi-word AGGREGATE ARRAY ELEMENT
## of a BY-REFERENCE ARRAY PARAM (`ps[0] == ps[1]` over `[P; 2]`) remains loud for unsupported
## element representations. The safe slice covers only plain structs whose fields are native scalar
## words; a string field must not be reduced to a raw word compare.
##
## Globals, enum/tuple elements, and unsupported aggregate roots keep the same fail-loud discipline.
P := struct { x : u64, s : str }
cmp := fn(ps : [P; 2]) -> u64 {
  if ps[0] == ps[1] { return 1 }
  return 42
}
main := fn() -> u64 {
  ps : [P; 2] = [P(x = 1, s = "a"), P(x = 1, s = "b")]
  cmp(ps)
}
