## The ancestor's own generic `f`, shadowed in `geo::child`.
f := fn(T : type, x : T) -> T { x + 100 }
pub pf := fn() -> u64 { f(u64, 0) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
