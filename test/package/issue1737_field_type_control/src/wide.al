## Module `wide`'s own `Inner`, one word, laid out inside `P` ahead of the field the caller reads.
pub Inner := struct { x : u64 }
pub P := struct { e : Inner, v : u64 }
pub mk := fn() -> P { return P(e = Inner(x = 7), v = 42) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
