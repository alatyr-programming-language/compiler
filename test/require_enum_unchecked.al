## §8.1 — unchecked removes the whole enum predicate path but keeps the complete tagged value.
Pair := enum { Good(u64, u64), Bad }

within := fn(p : Pair) -> bool {
  match p {
    Pair::Good(a, b) => { return a == 20 and b == 22 }
    Pair::Bad => { return false }
  }
}
consume := fn(p : Pair) -> u64 {
  match p {
    Pair::Good(a, b) => { return a + b }
    Pair::Bad => { return 0 }
  }
}
Checked := @require(within) Pair

main := fn() -> u64 {
  x := unchecked { Checked(Pair.Good(0, 42)) }
  return consume(x)
}
