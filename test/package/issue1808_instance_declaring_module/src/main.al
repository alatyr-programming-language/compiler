Node := struct { b : u64, a : u64 }
theirs := fn(h : usize) -> u64 { p : ptr(m::Node) = m::at(m::Node, h); deref(p).b }
own := fn(h : usize) -> u64 { q : ptr(Node) = unchecked bitcast(ptr(Node), h); deref(q).b }
mine := fn(h : usize) -> u64 { q : ptr(Node) = m::at(Node, h); deref(q).a }
main := fn() -> u64 {
  mut t : Node = Node(b = 30, a = 2)
  mut u : m::Node = m::Node(a = 1, b = 3)
  ht := unchecked bitcast(usize, ptr(t))
  hu := unchecked bitcast(usize, ptr(u))
  ## 30 + 2 + 3 + 3 + 3 + 1 = 42: each instance reads the layout of its own type argument.
  own(ht) + mine(ht) + theirs(hu) + m::mrd(hu) + m::msecond(hu) + m::second(Node, ht) / 30
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
