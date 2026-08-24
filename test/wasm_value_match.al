Box := enum { Empty, Full(u64) }
get := fn(b : Box) -> u64 {
  match b {
    Box::Empty => { 0 }
    Box::Full(v) => { v + 2 }
  }
}
main := fn() -> u64 { get(Box.Full(40)) }
