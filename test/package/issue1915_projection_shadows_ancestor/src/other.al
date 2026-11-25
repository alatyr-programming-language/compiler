## The functions `geo::child` projects.
pub f := fn(x : u64) -> u64 { x + 2 }
pub g := fn(x : u64) -> u64 { x + 1 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
