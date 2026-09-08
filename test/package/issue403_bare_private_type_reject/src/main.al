## `hid::Secret` is private and `main` is its SIBLING, not its descendant.
main := fn() -> u64 {
  x := Secret(v = 42)
  x.v
}
