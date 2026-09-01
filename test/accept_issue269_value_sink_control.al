## Issue #269 control — a wrapper passed to a matching wrapper parameter is still matched and returns 42.
make_result := fn() -> Result(u64, u64) { return Result(u64, u64).Ok(7) }
keep_result := fn(value : Result(u64, u64)) -> u64 {
  match value {
    Result::Ok(v) => { return v + 35 }
    Result::Err(_) => { return 1 }
  }
}
main := fn() -> u64 { return keep_result(make_result()) }
