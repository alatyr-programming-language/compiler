## P0 sema conformance: the implicit tail result has the same return boundary.

bad_tail := fn() -> u64 {
  "x"
}

main := fn() -> u64 {
  return bad_tail()
}
