## A constructor-initialized raw-union global stores its single payload at offset zero,
## with max-width padding and nested member reads using the same overlap layout.
Pair := struct { x : u64, y : u64 }
U := union { n(u64), p(Pair) }
mut G := U.p(Pair(x = 10, y = 32))
main := fn() -> u64 {
  return G.p.x + G.p.y
}
