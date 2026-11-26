## An unrelated sibling's `Node`: two words, `b` at offset 8. Never nameable bare from the root or `geo`.
pub Node := struct { a : u64, b : u64 }
pub zero := fn() -> u64 { return 0 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
