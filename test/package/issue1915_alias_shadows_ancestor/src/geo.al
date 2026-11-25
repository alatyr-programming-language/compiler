## The ancestor's own `f`, shadowed in `geo::child` and below.
f := fn(x : u64) -> u64 { x + 100 }
pub pf := fn() -> u64 { f(0) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
