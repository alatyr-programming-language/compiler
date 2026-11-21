Node := struct { b : u64, a : u64 }
A := Node
Id := brand(Node)
W := u64
main := fn() -> u64 {
  mut t : Node = Node(b = 10, a = 2)
  mut u : m::Node = m::Node(a = 1, b = 3)
  ht := unchecked bitcast(usize, ptr(t))
  hu := unchecked bitcast(usize, ptr(u))
  mut x : u64 = 258
  hx := unchecked bitcast(usize, ptr(x))
  ## 10 + 10 + 10 + 3 + 3 + 3 + 3 = 42: each instance reads the layout of the type its argument names.
  ## The root's `W` is `u64` and `m`'s is `u8`: 258 - 2 - 256 = 0.
  m::second(A, ht) + m::second(Node, ht) + m::second(Id, ht) + m::ma(hu) + m::mid(hu) + m::second(m::A, hu) + m::second(m::Id, hu) + m::rd(W, hx) - m::mw(hx) - 256
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
