## P0 sema conformance: a string result cannot inhabit a scalar u64 return slot.
## Before the fix this checks successfully, builds, and the runtime observes a value
## out of nowhere; the return sink must reject the mismatch before lowering.

bad := fn() -> u64 {
  return "x"
}

main := fn() -> u64 {
  v := bad()
  if v == 0 { return 42 }
  return 41
}
