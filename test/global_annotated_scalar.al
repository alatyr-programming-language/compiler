## ROADMAP §4/§1: a TYPE-ANNOTATED module-level binding `NAME : T = value` — the top-level dual of
## the annotated local `x : T = v`. parse_decl previously required `:=` after the name, so any
## annotated global (mut or const) was a spurious "parse error". Covers a `mut` annotated scalar
## global AND a const annotated scalar global. Returns 42 (40 + 2).
mut K : u64 = 40
C : u64 = 2
main := fn() -> u64 { return K + C }
