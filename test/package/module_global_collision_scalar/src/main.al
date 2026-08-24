## Expected exit code 42: 1 + 2 from the independent globals, plus 39.
main := fn() -> u64 {
  u64(left::limit()) + u64(right::limit()) + 39
}
