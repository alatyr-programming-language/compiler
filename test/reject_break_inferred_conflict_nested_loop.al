## P1-BREAK — nested loop control flow must diagnose the offending outer break value site.
## The inner loop is unrelated to the outer loop's value. The outer loop still conflicts on int vs bool.
main := fn() -> u64 {
  flag : bool = true
  cond : bool = true
  x := loop {
    inner := loop {
      break 7
    }
    if cond {
      break 1
    } else {
      break flag
    }
  }
  0
}
