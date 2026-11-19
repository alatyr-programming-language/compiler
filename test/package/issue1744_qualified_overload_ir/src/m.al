pub pick := fn(x : u64) -> u64 { x + 1 }
pub pick := fn(x : u8) -> u64 { u64(x) }
pub narrow := fn() -> u64 { pick(u8(1)) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
