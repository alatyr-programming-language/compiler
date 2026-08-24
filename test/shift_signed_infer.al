## `shr` returns the left operand's signed integer type. An unannotated bind from `shr(i64, n)`
## must therefore behave as signed in later operations; requiring `b : i64 = ...` was a lean
## type-inference gap.
main := fn() -> u64 {
  s : i64 = 0 - 40
  b := shr(s, 1)
  if b != (0 - 20) { return 1 }
  c := b / 2
  if c == (0 - 10) { return 42 }
  return 2
}
