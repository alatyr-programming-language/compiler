## Issue #805 / Control Flow §5.4 — the same short range list over a `usize` scrutinee.
f := fn(n : usize) -> u64 {
  match n { 0..=9 => { return 1 }; 10..=100 => { return 41 } }
  return 0
}
main := fn() -> u64 { return f(3) + f(1000) }
