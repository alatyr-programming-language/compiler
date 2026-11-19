pub T := struct { a : u64 }
pub pick := fn(t : T) -> u64 { t.a }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
