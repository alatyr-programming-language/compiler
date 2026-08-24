## A payloadless named enum CALL is one word and remains accepted by the same
## enum-payload construction path.
E := enum { A, B }

make_e := fn(k : u64) -> E {
  if k == 0 { return E.A }
  E.B
}

mk := fn(k : u64) -> Result(u64, E) {
  Result(u64, E).Err(make_e(k))
}

main := fn() -> u64 {
  match mk(0) {
    Ok(_) => { return 1 }
    Err(e) => {
      match e {
        A => { return 42 }
        B => { return 100 }
      }
    }
  }
  0
}
