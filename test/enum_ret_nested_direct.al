## e2e — `match <enum-returning call>` DIRECTLY (no intermediate binding): the call result is
## staged into the match scratch temp. A nested multi-word enum payload must stage all its words,
## not just word 0. run() -> R.Fail(Err.Bad(42)); inner match reads 42.
Err := enum { Bad(u64), Worse }
R := enum { Ok(u64), Fail(Err) }

run := fn() -> R { return R.Fail(Err.Bad(42)) }

main := fn() -> u64 {
  match run() {
    R::Ok(v) => { return 0 }
    R::Fail(e) => {
      match e {
        Err::Bad(x) => { return x }
        Err::Worse => { return 1 }
      }
    }
  }
}
