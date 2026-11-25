## The decoy, declared after `geo`: the same field names behind a leading `q`, so its layout differs.
pub S := struct { q : u64, a : u64, b : u64 }
pub keep := fn() -> u64 { s := S(q = 0, a = 1, b = 2); return s.b }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
