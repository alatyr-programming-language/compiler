## Issue #788 / Control Flow §5.1/§5.4 — a `bool` scrutinee is covered by `true` and `false`. Only
## `true` is written and no `_` default is present, so this must be refused; the parent skipped it.
main := fn() -> u64 {
  b := false
  match b { true => { return 11 } }
  return 0
}
