## The trailing-value form: `ptr(x)` as the fn's return value (the spec's exact ill-formed example).
f := fn() -> ptr(u64) {
  x := 5
  ptr(x)
}
main := fn() -> u64 { 0 }
