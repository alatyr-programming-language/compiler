## Issue #414 / Declarations §6.2 — the SAME-TYPE spelling of the same rule. This one is the reason
## the lowering fence is not a substitute: every backend accepted it and every backend answered 109,
## so nothing looked wrong, yet §6.2 calls the program ill-formed. The check must fire on the second
## binding's own source line whether or not the two types agree.
pick := fn() -> usize {
  r := Option(usize).Some(1)
  r := Option(usize).Some(9)
  mut out : usize = 77
  match r {
    Some(v) => { out = 100 + v }
    None => { out = 50 }
  }
  return out
}

main := fn() -> u64 { return u64(pick()) }
