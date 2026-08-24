## a TYPE-ANNOTATED module-level struct binding `mut STATE : S = S(...)` with an ENUM
## field, read via `match STATE.c`. Exercises the annotated-global parse path (kind-0 value decl, the
## `: T =` form) on an aggregate initializer. Returns 42 (40 + 2).
Col := enum { R, G(u64) }
S := struct { c : Col, n : u64 }
mut STATE : S = S(c = Col.G(40), n = 2)
main := fn() -> u64 { return match STATE.c { Col::R => { 0 }; Col::G(v) => { v } } + STATE.n }
