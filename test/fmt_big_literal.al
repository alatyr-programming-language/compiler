## fmt fixture — an integer literal at or above 2^63. `Expr::Num` carries an `i64` payload, so such a
## literal is stored as its BIT PATTERN, and fmt printed it through the SIGNED `rt::push_int`:
## The maximum u64 literal came back as `-1`. That is a different value twice over — and because the
## parser desugars every written `-x` into `unchecked 0 - x`, the re-parse also put an OVERFLOWING
## subtraction on a `u64` where a literal had stood, so the reformatted program died on the checked-
## arithmetic trap (SIGILL 132) instead of running. fmt now renders a negative `Num` payload
## unsigned; a source `-x` never reaches that arm, so the test is exact. Returns 42.
main := fn() -> u64 {
  m : u64 = 18446744073709551615
  h : u64 = 9223372036854775808
  mut acc : u64 = 0
  if m == 18446744073709551615 { acc = acc + 20 }
  if h == 9223372036854775808 { acc = acc + 22 }
  return acc
}
