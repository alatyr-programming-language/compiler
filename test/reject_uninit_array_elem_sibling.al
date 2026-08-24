## Writing one element does not initialize an unreadied sibling.
main := fn() -> u64 {
  mut xs : [u64; 2]
  xs[0] = 42
  return xs[1]
}
