## e2e — loop-as-expression break-value type-consistency GUARD (Control Flow §7.2): a bare `break`
## (no value, a diverging exit) imposes NO constraint on the loop's value type — `break 40` + bare
## `break` in the same value-loop must stay accepted.
main := fn() -> u64 {
  mut k : u64 = 0
  z := loop {
    if k == 0 {
      k = 1
      break 40
    }
    break
  }
  z - 40 + k                       ## 40 - 40 + 1 = 1; check only asserts acceptance
}
