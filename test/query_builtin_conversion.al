## P1-QUERY regression: a built-in numeric conversion must reject a `str` source in
## `compiles()`, while the valid numeric literal conversion remains true.
main := fn() -> u64 {
  good := compiles(u64(42))
  bad := compiles(u64("not-a-number"))
  if good and not bad { return 42 }
  return 1
}
