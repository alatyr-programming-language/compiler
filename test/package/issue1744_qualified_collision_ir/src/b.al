## The `f` a module path names; the root declares another `f`.
pub f := fn() -> u64 { 32 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
