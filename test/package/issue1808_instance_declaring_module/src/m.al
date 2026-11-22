pub Node := struct { a : u64, b : u64 }
pub at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
pub second := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); deref(p).b }
pub mrd := fn(h : usize) -> u64 { p : ptr(Node) = at(Node, h); deref(p).b }
pub msecond := fn(h : usize) -> u64 { second(Node, h) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
