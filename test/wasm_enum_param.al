Box := enum { Empty, Full(u64) }
get := fn(b : Box) -> u64 {
  match b {
    Box::Empty => 0
    Box::Full(v) => v
  }
}
main := fn() -> u64 {
  b := Box.Full(42)
  get(b)
}
