main := fn() -> u64 {
  r : Result(u64, u64) = Result.Ok(42)
  return r.unwrap()
}
