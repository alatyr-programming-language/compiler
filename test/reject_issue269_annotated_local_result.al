## Issue #269 / Types §4.1–§4.3 / Declarations §3.1 — a wrapper kept in an inferred local does not
## become its payload merely because a later annotated binding names that payload.
make_result := fn() -> Result(u64, u64) { return Result(u64, u64).Ok(7) }
bad := fn() -> u64 {
  wrapped := make_result()
  value : u64 = wrapped
  return value
}
main := fn() -> u64 { return 42 }
