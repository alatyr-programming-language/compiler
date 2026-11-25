## `m`'s own `S`, with other field names.
pub S := struct { x : u64, y : u64, z : u64 }
pub own := fn() -> u64 { s := S(x = 0, y = 0, z = 0); return s.x + s.y + s.z }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
