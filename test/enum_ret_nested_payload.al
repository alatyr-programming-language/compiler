## e2e — an enum RETURNED from a call whose payload is itself a MULTI-WORD enum. `run -> R`,
## R.Fail(Err), Err.Bad(u64). The inner `match e` must read the full payload word (42), not a
## truncated garbage word. Exercises the enum-return ABI beyond 2 words (nested enum payload).
Err := enum { Bad(u64), Worse }
R := enum { Ok(u64), Fail(Err) }

run := fn() -> R { return R.Fail(Err.Bad(42)) }

main := fn() -> u64 {
  r := run()
  match r {
    R::Ok(v) => { return 0 }
    R::Fail(e) => {
      match e {
        Err::Bad(x) => { return x }
        Err::Worse => { return 1 }
      }
    }
  }
}
