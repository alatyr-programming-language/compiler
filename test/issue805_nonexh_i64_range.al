## Issue #805 / Control Flow §5.4 — ranges over an `i64` must cover `[-2^63, 2^63 - 1]`. These stop at
## 100; the parent built it and `f(1000)` delivered 0.
f := fn(n : i64) -> u64 {
  r := match n { -9223372036854775808..=-1 => { 1 }; 0..=100 => { 41 } }
  return r
}
main := fn() -> u64 { return f(-3) + f(1000) }
