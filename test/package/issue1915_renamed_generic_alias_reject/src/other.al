## The generic function `geo::child` binds under another name.
pub h := fn(T : type, x : T) -> T { x + 2 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
