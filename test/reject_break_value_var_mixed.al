## e2e — break-value consistency must infer a known local type, not only literal tags.
main := fn() -> u64 {
  x := 1
  z := loop {
    if true { break x }
    break true
  }
  return z
}
