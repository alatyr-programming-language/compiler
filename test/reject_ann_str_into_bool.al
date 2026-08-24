## The same rule with a `bool` sink: `str` is not implicitly convertible to `bool` either (Types §4.3).
main := fn() -> u64 {
  x : bool = "nope"
  if x { return 1 }
  return 0
}
