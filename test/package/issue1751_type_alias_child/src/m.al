## `m`'s own `S` and its alias `T` of it.
pub S := struct { z : u64, y : u64, x : u64 }
pub T := S
pub viat := fn() -> u64 { t := T(x = 3, y = 0, z = 7); return t.x + t.z + t.y }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
