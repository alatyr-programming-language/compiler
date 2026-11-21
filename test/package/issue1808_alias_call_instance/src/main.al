Node := struct { b : u64, a : u64 }
P := m::Box(u8)
Q := ptr(Node)
R := uint(8)
S := m::Box(Node)
U := (Node, u64)
V := [Node; 2]
main := fn() -> u64 {
  ## 3 + 4 + 5 + 2 + 1 + 1 + 26 = 42, whatever the instances; their symbols are what the e2e row checks.
  m::tag(P, 3) + m::tag(Q, 4) + m::tag(R, 5) + m::tag(S, 2) + m::tag(U, 1) + m::tag(V, 1) + m::own()
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
