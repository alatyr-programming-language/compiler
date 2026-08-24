## A nested generic enum payload forwarded through an enum parameter must preserve every
## inner word: Result(u64, E) is passed by reference, then wrapped in Option(Result(...)).
E := enum { A(u64), B(u64) }

make_result := fn() -> Result(u64, E) {
  Result(u64, E).Err(E.A(7))
}

forward := fn(r : Result(u64, E)) -> Option(Result(u64, E)) {
  Option(Result(u64, E)).Some(r)
}

main := fn() -> u64 {
  match forward(make_result()) {
    Option::Some(r) => {
      match r {
        Result::Ok(_) => { return 1 }
        Result::Err(e) => {
          match e {
            A(v) => { return v + 35 }
            B(v) => { return v + 100 }
          }
        }
      }
    }
    Option::None => { return 2 }
  }
  0
}
