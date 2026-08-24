## e2e — base::str right-to-left search: rindex_of (last byte) and rfind_str (last substring), the duals
## of index_of/find_str. Covers a found last delimiter, a found last substring, and the None cases.
## Returns 42 iff all exact.
sm := base::str

main := fn() -> u64 {
  ri := sm::rindex_of("a/b/c", 47)               ## last '/' at index 3
  match ri { Option::Some(i) => { if i != 3 { return 1 } } Option::None => { return 1 } }
  rf := sm::rfind_str("abXcdXef", "X")            ## last "X" at index 5
  match rf { Option::Some(i) => { if i != 5 { return 2 } } Option::None => { return 2 } }
  rf2 := sm::rfind_str("hello", "z")              ## no match
  match rf2 { Option::Some(i) => { return 3 } Option::None => {} }
  ri2 := sm::rindex_of("nofound", 47)             ## no match
  match ri2 { Option::Some(i) => { return 4 } Option::None => {} }
  rf3 := sm::rfind_str("ababab", "ab")            ## last "ab" at index 4
  match rf3 { Option::Some(i) => { if i != 4 { return 5 } } Option::None => { return 5 } }
  return 42
}
