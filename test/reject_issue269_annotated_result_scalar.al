## Issue #269 / Types §4.1–§4.3 / Declarations §3.1 — a Result value remains a nominal wrapper
## when a local scalar annotation is used as the destination.
make_result := fn() -> Result(u64, u64) { return Result(u64, u64).Ok(7) }
bad := fn() -> u64 {
  value : u64 = make_result()
  return value
}
main := fn() -> u64 { return 42 }
