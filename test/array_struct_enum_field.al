## `match xs[i].c` directly over an ENUM FIELD of a struct-element array element
## (Field(Index(xs, i), c)). try_arrelem_field_enum_scrut destructures the Index via field_base_index,
## resolves the element struct's enum field, and materializes its words (element base via
## emit_index_addr, field at -(fwo+j)*8) into the match scratch. Both value- and statement-match paths.
Col := enum { R, G(u64) }
S := struct { c : Col, n : u64 }
main := fn() -> u64 {
  xs := [S(c = Col.G(40), n = 1), S(c = Col.R, n = 1)]
  return match xs[0].c { Col::R => { 0 }; Col::G(v) => { v } } + xs[0].n + xs[1].n
}
