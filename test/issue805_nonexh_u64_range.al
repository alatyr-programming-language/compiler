## Issue #805 / Control Flow §5.4 — ranges over a `u64` must cover `[0, 2^64 - 1]` or carry a `_`.
## These stop at 100; the parent built it and `f(1000)` delivered 0.
f := fn(n : u64) -> u64 {
  r := match n { 0..=9 => { 1 }; 10..=100 => { 41 } }
  return r
}
main := fn() -> u64 { return f(3) + f(1000) }
