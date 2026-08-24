## sema ptr-target discrimination (ROADMAP §6): passing a `ptr(mut B)` where a `ptr(mut A)` is
## expected is a type mismatch — the node-handle confusion class the usize->ptr migration guards.
A := struct { x : u64 }
B := struct { y : u64 }
takesA := fn(p : ptr(mut A)) -> u64 { return deref(p).x }
useB := fn(q : ptr(mut B)) -> u64 { return takesA(q) }
main := fn() -> u64 { return useB(unchecked bitcast(ptr(mut B), 0)) }
