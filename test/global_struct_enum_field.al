## a mutable-GLOBAL struct with an ENUM FIELD — `.data` layout (emit_global_data_cells
## emits the enum field as [disc, payload, pad] so a following scalar field aligns) and `match STATE.c`
## (try_field_enum_scrut materializes the field's enum from .data ascending, LABEL+(fwo+j)*8, into the
## match scratch — the global dual of the local struct-enum-field match). STATE.c = G(40), STATE.n = 2.
Col := enum { R, G(u64), B }
S := struct { c : Col, n : u64 }
mut STATE := S(c = Col.G(40), n = 2)
main := fn() -> u64 {
  return match STATE.c { Col::R => { 0 }; Col::G(v) => { v }; Col::B => { 1 } } + STATE.n
}
