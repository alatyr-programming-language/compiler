pub W := struct { v : u64 }
pub get := fn(w : W) -> u64 { return w.v }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
