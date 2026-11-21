## Issue #1810 — one generic instance written with different whitespace at different call sites is ONE
## instance (Comptime §3.4: identical comptime arguments share one instance). Mono's instance list
## compared type arguments by their text, so `ptr(u64)`, `ptr( u64 )` and `ptr(u64 )` were three
## entries under one label and the assembler refused the program (symbol already defined).
## spec: Comptime §3.2, §3.4
at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
r1 := fn(h : usize) -> u64 { p : ptr(ptr(u64)) = at(ptr(u64), h); deref(deref(p)) }
r2 := fn(h : usize) -> u64 { p : ptr(ptr(u64)) = at(ptr( u64 ), h); deref(deref(p)) }
r4 := fn(h : usize) -> u64 { p : ptr(ptr(u64)) = at(ptr(u64 ), h); deref(deref(p)) }
main := fn() -> u64 {
  mut w : u64 = 14
  mut pw : ptr(u64) = ptr(w)
  hp := unchecked bitcast(usize, ptr(pw))
  r1(hp) + r2(hp) + r4(hp)
}
## expect: run 42
