## The answer helper.
## Returns a constant.
## expect: run 42
answer := fn() -> u64 {
  return 42
}
## Program entry.
main := fn() -> u64 {
  return answer()
}
