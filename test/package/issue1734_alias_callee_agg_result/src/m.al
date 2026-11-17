## Module `m`'s own `S`, two words, returned and taken by value.
pub S := struct { a : u64, b : u64 }
pub mk := fn() -> S { return S(a = 10, b = 1) }
pub weigh := fn(s : S) -> u64 { return s.a * 2 + s.b }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
