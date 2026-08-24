## Control Flow §5.4 — scalar RANGE patterns. Half-open `a..b` matches `a <= x < b`; inclusive
## `a..=b` matches `a <= x <= b`. Verifies the boundary: 10 is NOT in `0..10` (falls to `0..=10`).
## a = 40 (5 in [0,10)), b = 2 (10 excluded by [0,10), caught by [0,10]) → 42.
main := fn() -> u64 {
  a := match 5  { 0..10 => 40 ; _ => 0 }
  b := match 10 { 0..10 => 99 ; 0..=10 => 2 ; _ => 0 }
  return a + b
}
