## The mirror direction: an aggregate literal is not implicitly a `str` either.
S := struct { a : u64, b : u64 }
main := fn() -> u64 {
  s : str = S(a = 1, b = 2)
  return s.len()
}
