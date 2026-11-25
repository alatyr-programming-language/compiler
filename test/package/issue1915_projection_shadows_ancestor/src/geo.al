## The ancestor's own `f` and `g`, shadowed in `geo::child`. `g` takes two parameters, so a checker
## that judged `geo::child`'s `g(41)` against it would refuse a valid call.
f := fn(x : u64) -> u64 { x + 100 }
g := fn(x : u64, y : u64) -> u64 { x + y + 100 }
pub pf := fn() -> u64 { f(0) + g(0, 0) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
