## Issue #269 / Types §4.1–§4.3 / Declarations §3.1 — an Option value remains a nominal wrapper
## when a local scalar annotation is used as the destination.
make_option := fn() -> Option(u64) { return Option(u64).Some(7) }
bad := fn() -> u64 {
  value : u64 = make_option()
  return value
}
main := fn() -> u64 { return 42 }
