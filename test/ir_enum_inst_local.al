## IR #1033 step 2: a generic enum instance whose one payload component is an AGGREGATE, as a LOCAL that
## no signature carries — built in place, copied whole, and matched with the component bound by copying
## its bytes out of the payload (`lower_layout::enum_layout`, `agg_words`, Types §6.2). No signature
## carries one, so every function here is IR-built on all four backends: a signature carrying such an
## instance stays legacy on aarch64, riscv64 and wasm (`ir::sig_pins_legacy`).
##   * `Option(P)`: both variants, a copy `q := o` that a later rebinding cannot reach;
##   * `Result(u64, Error)`: an enum component, matched again inside the arm;
##   * `Option(Option(u64))`: an enum instance inside an enum instance.
## Each check returns its own code on failure; 42 when all hold.
P := struct { x : u64, y : u64 }
Error := enum { Missing, Bad(u64) }

opt := fn(k : u64) -> u64 {
  mut o : Option(P) = Option(P).None
  if k != 0 { o = Option(P).Some(P(x = k, y = k + 1)) }
  q := o
  o = Option(P).Some(P(x = 90, y = 9))
  match q { Option::Some(p) => { return p.x + p.y }; Option::None => { return 50 } }
}

res := fn(k : u64) -> u64 {
  mut r : Result(u64, Error) = Result(u64, Error).Ok(k * 2)
  if k == 0 { r = Result(u64, Error).Err(Error.Missing) }
  if k > 9 { r = Result(u64, Error).Err(Error.Bad(k)) }
  match r {
    Result::Ok(v) => { return v }
    Result::Err(e) => { match e { Error.Missing => { return 60 }; Error.Bad(b) => { return 70 + b } } }
  }
}

nest := fn(k : u64) -> u64 {
  mut o : Option(Option(u64)) = Option(Option(u64)).None
  if k == 1 { o = Option(Option(u64)).Some(Option(u64).None) }
  if k > 1 { o = Option(Option(u64)).Some(Option(u64).Some(k)) }
  match o {
    Option::Some(inner) => { match inner { Option::Some(v) => { return v }; Option::None => { return 2 } } }
    Option::None => { return 1 }
  }
}

main := fn() -> u64 {
  if opt(3) != 7 { return 1 }
  if opt(0) != 50 { return 2 }
  if res(4) != 8 { return 3 }
  if res(0) != 60 { return 4 }
  if res(12) != 82 { return 5 }
  if nest(0) != 1 or nest(1) != 2 or nest(9) != 9 { return 6 }
  opt(20) + 1
}
## expect: run 42
