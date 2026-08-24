## e2e — Types §9.1 at the SIGNED 64-bit boundary. `18446744073709551616` (2^64) has been a located
## parser reject ("does not fit in 64 bits") for a while, but `9223372036854775808` (2^63) fits 64
## bits and does NOT fit `i64` — it was accepted in silence and bound as the bit pattern, i.e. as
## i64::MIN. `Expr::Num` carries an `i64`, so this is exactly the case where the payload comes back
## NEGATIVE; the grammar has no negative literal (unary `-x` is `unchecked 0 - x`, not a `Num`), so a
## negative payload proves the written literal was at or above 2^63. Located at the binding (line 8).
main := fn() -> i64 {
  x : i64 = 9223372036854775808
  return x
}
