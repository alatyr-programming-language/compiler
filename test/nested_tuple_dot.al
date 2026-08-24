## Nested tuple element access via DOT syntax (t.0.0). Previously the lexer greedily read `0.0` as a
## float token, so t.0.0 = t.<float> mis-parsed to 0; the lexer now keeps a digit run that starts
## right after a `.` an integer (a tuple index), not a float. Both inferred and annotated tuples.
main := fn() -> u64 {
  t := ((30, 2), 10)
  a : ((u64, u64), u64) = ((1, 2), 3)
  return t.0.0 + t.0.1 + t.1 + a.0.0 + a.0.1 + a.1 - 6
}
