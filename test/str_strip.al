## e2e — base::str strip_prefix/strip_suffix (allocation-free str VIEWs): remove a known lead/tail if
## present, else return the string unchanged. Covers a present prefix, an absent prefix (unchanged), a
## present suffix, and an absent suffix. Returns 42 iff all exact.
sm := base::str

main := fn() -> u64 {
  a := sm::strip_prefix("http://x.com", "http://")
  if not (a == "x.com") { return 1 }
  b := sm::strip_prefix("hello", "xyz")
  if not (b == "hello") { return 2 }
  c := sm::strip_suffix("file.txt", ".txt")
  if not (c == "file") { return 3 }
  d := sm::strip_suffix("file.txt", ".md")
  if not (d == "file.txt") { return 4 }
  return 42
}
