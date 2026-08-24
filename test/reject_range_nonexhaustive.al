## sema/§5.4 — a `u8` scalar range match leaving [101,255] uncovered with NO `_` is NON-exhaustive
## and MUST be rejected (a compile error). `check` returns 1.
main := fn() -> u64 {
  n : u8 = 200
  r := match n { 0..=100 => 1 }
  return r
}
