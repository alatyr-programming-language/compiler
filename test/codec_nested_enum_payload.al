## A nullary user enum carried by Result must preserve its discriminant through
## construction, match binding, comparison, and a second function-call boundary.
E := enum { A, B, C, D }

eqc := fn(e : E) -> u64 {
  if e == E.A { return 0 }
  if e == E.B { return 1 }
  if e == E.C { return 2 }
  if e == E.D { return 3 }
  9
}

mk := fn(k : u64) -> Result(u64, E) {
  if k == 0 { return Result(u64, E).Err(E.A) }
  if k == 1 { return Result(u64, E).Err(E.B) }
  if k == 2 { return Result(u64, E).Err(E.C) }
  Result(u64, E).Err(E.D)
}

main := fn() -> u64 {
  mut acc : u64 = 0
  mut k : u64 = 0
  while k < 4 {
    match mk(k) {
      Ok(_) => { return 1 }
      Err(e) => { acc = acc + eqc(e) }
    }
    k = k + 1
  }
  acc + 36
}
