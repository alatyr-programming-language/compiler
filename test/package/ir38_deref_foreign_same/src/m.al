pub S := struct { x : u64, y : u64, a : u64 }
pub H := struct { p : ptr(S), k : u64 }
pub mk := fn() -> S { S(x = 1, y = 0, a = 20) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
