## A multi-word named enum literal and a CALL returning the same enum preserve the full
## Result payload layout.
E := enum { A(u64), B(u64) }

mk := fn(k : u64) -> Result(u64, E) {
  if k == 0 { return Result(u64, E).Err(E.A(7)) }
  Result(u64, E).Err(E.B(9))
}

main := fn() -> u64 {
  match mk(0) {
    Ok(_) => { return 1 }
    Err(e) => {
      match e {
        A(v) => { return v + 35 }
        B(v) => { return v + 100 }
      }
    }
  }
  0
}
