## Issue #788 / Control Flow §5.1/§5.4 — a `bool` VALUE match with only a `true` arm. The parent built
## it and bound `r` to 0 for `b = false`, a value no arm covers.
main := fn() -> u64 {
  b := false
  r := match b { true => { 11 } }
  return r
}
