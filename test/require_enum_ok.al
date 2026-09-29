## §8.1 aggregate validity contract — an enum underlying type keeps its complete tagged layout
## through checked construction, an ordinary predicate copy, aggregate argument passing, and return.
## `consume` takes the REQUIRED type: §8.1 makes `U` and `R` assignment-incompatible in both
## directions, so a `Checked` argument into a `Pair` parameter is ill-formed. It was accepted only
## while `check_expr`'s `Call` arm had never run and `y := make_checked()` recorded no type (#726).
Pair := enum { Good(u64, u64), Bad }

within := fn(p : Pair) -> bool {
  match p {
    Pair::Good(a, b) => { return a == 20 and b == 22 }
    Pair::Bad => { return false }
  }
}
consume := fn(p : Checked) -> u64 {
  match p {
    Pair::Good(a, b) => { return a + b }
    Pair::Bad => { return 0 }
  }
}

Checked := Pair.require(within)
make_pair := fn() -> Pair { return Pair.Good(20, 22) }
make_checked := fn() -> Checked { return Checked(Pair.Good(20, 22)) }

main := fn() -> u64 {
  x := Checked(Pair.Good(20, 22))
  if consume(x) != 42 { return 1 }
  raw := Pair.Good(20, 22)
  z := Checked(raw)
  if consume(z) != 42 { return 2 }
  q := Checked(make_pair())
  if consume(q) != 42 { return 3 }
  y := make_checked()
  if consume(y) != 42 { return 4 }
  return consume(Checked(Pair.Good(20, 22)))
}
