## P1 signedness: a fixed-array parameter is passed by reference, but its indexed
## u64 element still has a declared unsigned type. The old scan rejected is_ref
## entries and fell back to signed ordering at the high-bit boundary.
check := fn(a : [u64; 2]) -> u64 {
  if a[0] < a[1] { return 42 }
  return 1
}

main := fn() -> u64 {
  xs : [u64; 2] = [0, 18446744073709551615]
  check(xs)
}
