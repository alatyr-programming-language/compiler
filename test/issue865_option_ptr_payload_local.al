## #865 — a local annotated `Option(ptr(T))` and initialized from a component of a multi-payload
## variant's pattern was refused ("cannot see the scrutinee's enum type") when matched.
##
## `collect_slots` sized the local from its initializer's form, and the pattern component is typed only
## at emit time, so the local got an untyped scalar slot even with the annotation. The annotation alone
## now makes it the one-word folded Option (Types §6.2); `match h` directly always worked.

Node := struct { v : i64, next : Option(ptr(mut Node)) }
Shape := enum { Leaf(i64), Chain(i64, Option(ptr(mut Node)), i64), Empty }

## `n` is annotated `Option(ptr(mut Node))` and initialized from `h`, a component of a multi-payload
## variant's pattern. The annotation alone makes it the one-word folded Option.
total := fn(e : Shape) -> i64 {
  mut r : i64 = 0
  match e {
    Shape::Chain(a, h, c) => {
      mut n : Option(ptr(mut Node)) = h
      loop {
        match n {
          Some(q) => { nd := deref(q); r += nd.v; n = nd.next }
          None => { break }
        }
      }
      r += a + c
    }
    Shape::Leaf(x) => { r = x }
    Shape::Empty => { r = 0 }
  }
  r
}

main := fn() -> i64 {
  mut n3 : Node = Node(v = 20, next = Option.None)
  mut n2 : Node = Node(v = 10, next = Option.Some(ptr(n3)))
  chain := Shape.Chain(7, Option.Some(ptr(n2)), 5)
  mut got := total(chain)
  if total(Shape.Leaf(9)) != 9 { got = 1 }
  if total(Shape.Empty) != 0 { got = 2 }
  got
}
