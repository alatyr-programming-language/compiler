## `S` is neither declared here nor imported (Modules §3): ill-formed.
pub H := struct { p : ptr(S), k : u64 }
pub mk := fn(q : ptr(S), k : u64) -> H { H(p = q, k = k) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
