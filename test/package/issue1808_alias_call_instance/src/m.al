pub Node := struct { a : u64, b : u64 }
pub Box(T) := struct { v : T, w : T }
pub P := Box(u64)
pub Q := ptr(Node)
pub R := uint(64)
pub S := Box(Node)
pub U := (Node, u64)
pub V := [Node; 2]
pub tag := fn(T : type, k : u64) -> u64 { k }
pub own := fn() -> u64 { tag(P, 6) + tag(Q, 5) + tag(R, 4) + tag(S, 9) + tag(U, 1) + tag(V, 1) }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
