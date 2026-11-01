cfg : u64 = 3
pub get := fn() -> u64 { z::cfg.x + cfg }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
