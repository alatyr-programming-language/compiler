## The answer helper.
## Returns a constant.
answer := fn() -> u64 {
  return 42
}
## Program entry.
main := fn() -> u64 {
  return answer()
}
## expect(x86_64): run 42
