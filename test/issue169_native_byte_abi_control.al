## Control for #169: exercise a pair return flowing into a pair parameter, while a wider mixed struct
## remains on the existing word-granular carrier. The pair checks both fields after the round trip.

Pair := struct { a : u8, b : u8 }
Word := struct { a : u8, n : u64 }

round_pair := fn(s : Pair) -> Pair {
  Pair(a = s.a, b = s.b)
}

take_pair := fn(s : Pair) -> u64 {
  u64(s.a) * 10 + u64(s.b)
}

take_word := fn(s : Word) -> u64 {
  u64(s.a) + s.n
}

main := fn() -> u64 {
  source := Pair(a = 7, b = 5)
  roundtrip := round_pair(source)
  control := Word(a = 3, n = 39)
  if take_pair(roundtrip) != 75 { return 1 }
  if take_word(control) != 42 { return 2 }
  42
}
