## `m`'s own generic `at` reads the word after the handle; the root's reads the handle's own word.
at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h + 8) }
## Built from the shared IR: the bare `at` here is `m`'s.
pub mown := fn(h : usize) -> u64 {
  p : ptr(u64) = at(u64, h)
  deref(p)
}
pub pick := fn(T : type, a : T, b : T) -> T { b }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
