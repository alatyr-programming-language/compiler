## A raw union is an untagged overlapping value. Whole-value copy must preserve all words of
## the widest single-payload member, without introducing an enum discriminant.
Pair := struct { x : u64, y : u64 }
U := union { n(u64), p(Pair) }
main := fn() -> u64 {
  a := U.p(Pair(x = 10, y = 32))
  b := a
  return b.p.x + b.p.y
}
