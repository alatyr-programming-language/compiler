pub Node := struct { a : u64, b : u64 }
pub A := Node
pub Id := brand(Node)
pub second := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); deref(p).b }
pub ma := fn(h : usize) -> u64 { second(A, h) }
pub mid := fn(h : usize) -> u64 { second(Id, h) }
pub W := u8
pub rd := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); u64(deref(p)) }
pub mw := fn(h : usize) -> u64 { rd(W, h) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
