## extract an enum/struct field of a mutable-GLOBAL struct into a local
## (`c := STATE.c`). global_field_agg copies the field's words from .data (ASCENDING) into the local.
## Completes the global-struct-enum-field story (layout + match STATE.c + this bind).
Col := enum { R, G(u64) }
S := struct { c : Col, n : u64 }
mut STATE := S(c = Col.G(40), n = 2)
main := fn() -> u64 {
  c := STATE.c
  return match c { Col::R => { 0 }; Col::G(v) => { v } } + STATE.n
}
