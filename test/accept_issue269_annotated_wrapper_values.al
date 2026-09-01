## Issue #269 control / Types §4.1–§4.3 — an explicitly annotated wrapper may receive the same
## wrapper type; no implicit projection is needed or allowed.
make_result := fn() -> Result(u64, u64) { return Result(u64, u64).Ok(7) }
make_option := fn() -> Option(u64) { return Option(u64).Some(8) }
keep_result := fn() -> Result(u64, u64) {
  value : Result(u64, u64) = make_result()
  return value
}
keep_option := fn() -> Option(u64) {
  value : Option(u64) = make_option()
  return value
}
main := fn() -> u64 { return 42 }
