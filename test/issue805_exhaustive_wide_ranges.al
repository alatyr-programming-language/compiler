## Issue #805 / Control Flow §5.4 — the over-rejection control for 64-bit UNSIGNED ranges: arms that
## cover all of `[0, 2^64 - 1]` over a `u64` and a `usize`, with no `_`, are exhaustive and `check`
## accepts them. (Run-time matching of a range whose bound is at or above 2^63 is #806; the checker's
## verdict is the property under test here.)
wide := fn(n : u64) -> u64 {
  r := match n { 0..=9 => { 1 }; 10..=18446744073709551615 => { 4 } }
  return r
}
word := fn(n : usize) -> u64 {
  match n { 0..100 => { return 1 }; 100..=18446744073709551615 => { return 5 } }
  return 0
}
main := fn() -> u64 { return wide(3) + word(7) }
