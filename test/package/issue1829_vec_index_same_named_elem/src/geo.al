## `geo`'s own `Node`: three words, `b` at offset 16. Not `pub`: §3 makes it visible to `geo::child`.
Node := struct { z : u64, y : u64, b : u64 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
