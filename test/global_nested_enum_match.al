## matching an ENUM field of a NESTED struct field of a mutable-global struct
## (`match STATE.i.c`). try_field_enum_scrut now resolves the scrutinee via global_place (any depth)
## and materializes the enum from .data ascending into the match scratch. G(35) + n(7) = 42.
Col := enum { R, G(u64) }
Inner := struct { c : Col, k : u64 }
Outer := struct { i : Inner, n : u64 }
mut STATE := Outer(i = Inner(c = Col.G(35), k = 0), n = 7)
main := fn() -> u64 { return match STATE.i.c { Col::R => { 0 }; Col::G(v) => { v } } + STATE.n }
