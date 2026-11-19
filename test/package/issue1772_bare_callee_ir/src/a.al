## Decoys: `main` or `b` declares or imports each of these names too, and each answer here would change
## the total if a bare call bound to it.
pub twice := fn(x : u64) -> u64 { x * 2 }
pub step := fn(x : u64) -> u64 { x + 1 }
pub half := fn(x : u64) -> u64 { x + 100 }
pub dec := fn(x : u64) -> u64 { x + 100 }
pub pick := fn(x : u64) -> u64 { x + 100 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
