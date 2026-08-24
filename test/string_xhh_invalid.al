## An escaped byte outside a valid UTF-8 sequence is rejected as a str literal.
main := fn() -> u64 {
  s := "\xff"
  s.len
}
