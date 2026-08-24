## ROADMAP §4: READING a scalar field of a NESTED struct field of a mutable-global struct
## (`STATE.inner.a`). Global field access was 1-level only (base must be a Var global); this reads
## `LABEL + (fwo(inner) + fwo(a in P))*8`. inner=P(a=10,b=27), n=5 → 10 + 27 + 5 = 42.
P := struct { a : u64, b : u64 }
Outer := struct { inner : P, n : u64 }
mut STATE := Outer(inner = P(a = 10, b = 27), n = 5)
main := fn() -> u64 { return STATE.inner.a + STATE.inner.b + STATE.n }
