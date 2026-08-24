## A generic enum carrying a MULTI-WORD generic-enum VALUE as payload — `Option(Result(u64, u64))` —
## works for both an enum-returning CALL and an enum VAR. Construction, whole-value staging, and the
## inner match preserve the outer discriminant plus every word of the nested Result.

inner := fn(x : u64) -> Result(u64, u64) { return Result.Ok(42) }

main := fn() -> u64 {
  r := inner(1)
  o := Option.Some(r)                ## Option carrying a multi-word Result VALUE
  match o {
    Option::Some(rr) => {
      match rr {
        Result::Ok(v) => { return v }
        Result::Err(e) => { return e }
      }
    }
    Option::None => { return 7 }
  }
}
