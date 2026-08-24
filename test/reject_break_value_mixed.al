## e2e — loop-as-expression break-value type consistency (Control Flow §7.2): "break-values of
## incompatible type are ill-formed". This loop's two break exits carry an `int` (tag 1) and a `str`
## (tag 6) — KNOWN incompatible types — so `alatyr check` must REJECT the program (was accepted, and
## the build silently emitted a binary whose `z` would be a str {ptr,len} pair read as a scalar).
main := fn() -> u64 {
  mut k : u64 = 0
  z := loop {
    k = k + 1
    if k == 1 { break 1 }
    break "abc"
  }
  return z + k
}
