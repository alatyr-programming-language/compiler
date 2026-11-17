## `T` is declared only here; it names this module's two-word `Inner`.
Inner := struct { a : u64, b : u64 }
T := Inner
pub mk := fn() -> T { Inner(a = 20, b = 22) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
