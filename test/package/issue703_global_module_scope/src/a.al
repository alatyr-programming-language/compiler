P := struct { x : u64 }
cfg : P = P(x = 5)
lim : u64 = 7
pub get := fn() -> u64 { cfg.x + lim }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
