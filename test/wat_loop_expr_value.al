## WAT bounded slice: scalar loop expressions yield a literal break and a conditional local break.
## Both exits must carry the loop value to the assignment and preserve the surrounding local frame.
main := fn() -> u64 {
  first := loop {
    break 40
  }
  mut i : u64 = 0
  second := loop {
    i = i + 1
    if i == 2 { break i }
  }
  first + second
}
