## e2e — two break exits carrying locals of the same inferred integer type remain accepted.
main := fn() -> u64 {
  x := 10
  y := 20
  z := loop {
    if true { break x }
    break y
  }
  return z
}
