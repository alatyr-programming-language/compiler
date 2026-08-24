## e2e — base::str byte/substring search + numeric parse, now reachable (the functions existed but were
## not `pub` → a user program could not call them). Exercises starts_with/ends_with/contains_str/count_str
## (incl. non-overlapping counting)/find_str/index_of/parse_uint/parse_int/str_cmp. Returns 42 iff exact.
## Each aggregate-returning call (Option(...)) is bound to a LOCAL before matching (the lean lower does not
## pass a nested aggregate-returning call directly as an argument).
sm := base::str

main := fn() -> u64 {
  if not sm::starts_with("hello", "he") { return 1 }
  if sm::starts_with("hello", "lo") { return 2 }
  if not sm::ends_with("hello", "lo") { return 3 }
  if not sm::contains_str("hello world", "o w") { return 4 }
  if sm::contains_str("abc", "xyz") { return 5 }
  if sm::count_str("aXbXcX", "X") != 3 { return 6 }
  if sm::count_str("aaaa", "aa") != 2 { return 7 }              ## non-overlapping

  f := sm::find_str("hello", "ll")
  match f {
    Option::Some(i) => { if i != 2 { return 8 } }
    Option::None => { return 8 }
  }

  ix := sm::index_of("hello", 108)                              ## 'l' == 108
  match ix {
    Option::Some(i) => { if i != 2 { return 9 } }
    Option::None => { return 9 }
  }

  pu := sm::parse_uint("123")
  match pu {
    Option::Some(v) => { if v != 123 { return 10 } }
    Option::None => { return 10 }
  }

  pin := sm::parse_int("-45")
  match pin {
    Option::Some(v) => { if v != (0 - 45) { return 11 } }
    Option::None => { return 11 }
  }

  if not (sm::str_cmp("abc", "abd") < 0) { return 12 }
  if not (sm::str_cmp("abc", "abc") == 0) { return 13 }
  if not (sm::str_cmp("abd", "abc") > 0) { return 14 }
  return 42
}
