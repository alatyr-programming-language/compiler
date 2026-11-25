## `k`'s `S` is an alias of `n`'s struct.
S := n::S
pub viak := fn() -> u64 { v := S(b = 20, a = 2); return v.a + v.b }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
