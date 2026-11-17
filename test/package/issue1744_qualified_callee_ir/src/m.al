## `Q` is declared only here. `S` is declared here and, with another layout, in `main`.
Q := struct { a : u64, b : u64 }
S := struct { v : u64, w : u64 }
pub add := fn(x : u64, y : u64) -> u64 { x + y }
pub mkq := fn(a : u64, b : u64) -> Q { Q(a = a, b = b) }
pub mks := fn(v : u64, w : u64) -> S { S(v = v, w = w) }
pub get := fn(s : S) -> u64 { s.w }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
