## The bare Option.Some form has no payload type at the constructor site; the
## enum-returning call is the witness used to synthesize the complete payload type.
E := enum { A(u64), B(u64) }

inner := fn() -> E { E.A(7) }

main := fn() -> u64 {
  o := Option.Some(inner())
  match o {
    Option::Some(e) => {
      match e { A(v) => { return v + 35 } B(v) => { return v + 100 } }
    }
    Option::None => { return 1 }
  }
  0
}
