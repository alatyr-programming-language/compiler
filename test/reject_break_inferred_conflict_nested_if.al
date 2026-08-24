## P1-BREAK — nested conditional inference must diagnose the offending break value site.
## The first break establishes an int loop value. The nested if's break carries a bool local.
main := fn() -> u64 {
  flag : bool = true
  cond : bool = true
  x := loop {
    if cond {
      if cond {
        break 1
      } else {
        break 2
      }
    } else {
      break flag
    }
  }
  0
}
