## ROADMAP §4: MUTATING an enum field of a mutable-GLOBAL struct (`STATE.c = Col.G(v)`). The global
## field-write path stored a single word, dropping the enum payload (stale disc → wrong match arm);
## now it materializes the enum via emit_enum_assign and copies its [disc, payload…] words to .data
## ASCENDING (the write dual of the global-base enum-field read). R → G(37); match 37 + n(5) = 42.
Col := enum { R, G(u64) }
S := struct { c : Col, n : u64 }
mut STATE := S(c = Col.R, n = 5)
main := fn() -> u64 {
  STATE.c = Col.G(37)
  return match STATE.c { Col::R => { 0 }; Col::G(v) => { v } } + STATE.n
}
