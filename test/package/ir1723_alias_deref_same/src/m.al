pub E := enum { A, B(u64), C(u64, u64) }
pub mke := fn() -> E { E.C(40, 2) }
pub gete := fn(q : ptr(E)) -> ptr(E) { q }
pub S := struct { x : u64, y : u64, a : u64 }
pub mks := fn() -> S { S(x = 1, y = 0, a = 21) }
pub gets := fn(p : ptr(mut S)) -> ptr(mut S) { p }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
