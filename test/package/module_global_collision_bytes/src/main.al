## Expected exit code 42: 2 from the left table, 20 from the right, plus 20.
main := fn() -> u64 {
  u64(left::pick(1)) + u64(right::pick(1)) + 20
}
