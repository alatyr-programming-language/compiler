## Nested tuple element access via BRACKET syntax (t[0][0]) — works (the dot form t.0.0 mis-lexes
## `0.0` as a float; bracket is the workaround). Locks nested-tuple indexing.
main := fn() -> u64 {
  t := ((30, 2), 10)
  return t[0][0] + t[0][1] + t[1]
}
