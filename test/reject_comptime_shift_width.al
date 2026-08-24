## e2e — CT-12: an OVER-WIDTH shift at comptime (`shl(v, n)` with `n >= width`, OP-6/I11) is a located
## diagnostic, not a deferred trap. Located at the shift (line 3).
K : u64 = shl(1, 64)

main := fn() -> i64 {
  return i64(K)
}
