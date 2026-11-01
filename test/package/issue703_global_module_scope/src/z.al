Q := struct { y : u64 }
cfg : u64 = 3
lim : Q = Q(y = 4)
pub other := fn() -> u64 { cfg + lim.y }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
