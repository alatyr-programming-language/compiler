## P1-BREAK — inferred break-value conflict should diagnose the offending break value site.
## The first break establishes an int loop value. The second break carries a bool local, so the
## conflict is known only after local inference. `alatyr check` should reject at `flag`, not at `main`.
main := fn() -> u64 {
  flag : bool = true
  cond : bool = true
  x := loop {
    if cond {
      break 1
    } else {
      break flag
    }
  }
  0
}
