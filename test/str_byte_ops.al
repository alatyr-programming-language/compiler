## e2e — base::str byte helpers: count_byte (occurrences of a byte) and common_prefix_len (shared
## leading bytes of two strings). Allocation-free. Returns 42 iff all exact.
sm := base::str

main := fn() -> u64 {
  if sm::count_byte("a,b,c,d", 44) != 3 { return 1 }             ## 3 commas
  if sm::count_byte("hello", 122) != 0 { return 2 }              ## no 'z'
  if sm::count_byte("aaaa", 97) != 4 { return 3 }
  if sm::common_prefix_len("foobar", "foobaz") != 5 { return 4 } ## "fooba"
  if sm::common_prefix_len("abc", "xyz") != 0 { return 5 }
  if sm::common_prefix_len("prefix", "pre") != 3 { return 6 }    ## shorter bounds it
  if sm::common_prefix_len("same", "same") != 4 { return 7 }
  return 42
}
