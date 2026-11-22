pub rd := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); u64(deref(p)) }
C := u8
pub mm := fn(h : usize) -> u64 {
  c := rd(C, h)
  rd(k::C, h) / 256
}
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
