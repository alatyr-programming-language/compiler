pub rd := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); u64(deref(p)) }
(a, b) := zz
pub mm := fn(h : usize) -> u64 { rd(a::C, h) / 256 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
