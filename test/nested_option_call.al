## `match` on a call returning a generic enum whose payload is itself a MULTI-WORD enum
## (`outer(x)` returns `Option(Result(u64, u64))`, built as `Option.Some(inner(x))`) stages and
## matches the complete nested value without dropping the inner payload.

inner := fn(x : u64) -> Result(u64, u64) { return Result.Ok(42) }

outer := fn(x : u64) -> Option(Result(u64, u64)) { return Option.Some(inner(x)) }

main := fn() -> u64 {
  match outer(1) {
    Option::Some(r) => {
      match r {
        Result::Ok(v) => { return v }
        Result::Err(e) => { return e }
      }
    }
    Option::None => { return 7 }
  }
}
