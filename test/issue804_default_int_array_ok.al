## Issue #804 — the OVER-REJECTION control: an ANNOTATED `a : [u8; 2] = [1, 7]` passed to a `[u8; 2]`
## parameter, and a default-typed `b := [30, 5]` (an `[i64; 2]`) passed to an `[i64; 2]` parameter,
## both stay accepted. 7 + 35 = 42.
first := fn(xs : [u8; 2]) -> u64 { return u64(xs[1]) }
sumi := fn(xs : [i64; 2]) -> i64 { return xs[0] + xs[1] }
main := fn() -> u64 {
  a : [u8; 2] = [1, 7]
  b := [30, 5]
  return first(a) + u64(sumi(b))
}
