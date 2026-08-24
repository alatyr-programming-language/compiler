## focused review fixture — operator equality must keep a Slice(str) element on the str pair path.
main := fn() -> u64 {
  arr := ["ab", "cde"]
  s := arr[0..2]
  if s[0] == "ab" and s[1] == "cde" { return 42 }
  return 1
}
