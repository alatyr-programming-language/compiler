Box := enum { Empty, Full(u64) }
mut B := Box.Full(42)
main := fn() -> u64 {
  match B {
    Box::Empty => 0
    Box::Full(v) => v
  }
}
