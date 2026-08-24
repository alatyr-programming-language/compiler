## P1 signedness: a declared builtin integer element of a Slice(T) parameter must
## select unsigned ordering. The old index scan only understood fixed arrays,
## so Slice(u64)[i] fell back to signed `setl` at the high-bit boundary.
check := fn(s : Slice(u64)) -> u64 {
  if s[0] < s[1] { return 42 }
  return 1
}

main := fn() -> u64 {
  xs : [u64; 2] = [0, 18446744073709551615]
  check(xs[0..2])
}
