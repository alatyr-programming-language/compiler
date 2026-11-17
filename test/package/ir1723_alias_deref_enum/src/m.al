pub E := enum { A, B(u64), C(u64, u64) }
pub mk := fn() -> E { E.C(40, 2) }
pub get := fn(q : ptr(E)) -> ptr(E) { q }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
