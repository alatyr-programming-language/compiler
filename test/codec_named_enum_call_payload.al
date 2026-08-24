## A CALL returning a named multi-word enum can be used as a Result payload while
## preserving the complete inner enum value.
E := enum { A(u64), B(u64) }

make_e := fn(k : u64) -> E {
  if k == 0 { return E.A(7) }
  E.B(9)
}

mk := fn(k : u64) -> Result(u64, E) {
  Result(u64, E).Err(make_e(k))
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
