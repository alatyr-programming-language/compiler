## §8.1 — a checked enum contract traps at the constructor when the predicate rejects the tag/payload.
Pair := enum { Good(u64, u64), Bad }

within := fn(p : Pair) -> bool {
  match p {
    Pair::Good(a, b) => { return a == 20 and b == 22 }
    Pair::Bad => { return false }
  }
}
Checked := Pair.require(within)

main := fn() -> u64 {
  x := Checked(Pair.Bad)
  return 42
}
