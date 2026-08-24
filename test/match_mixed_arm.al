## Control Flow §5.4 — a statement `match` mixing a literal arm, an OR arm, and a range arm.
## n = 15 falls into the inclusive range `10..=20` → 42.
main := fn() -> u64 {
  n := 15
  mut r := 0
  match n {
    0       => { r = 1 }
    1 | 2   => { r = 2 }
    10..=20 => { r = 42 }
    _       => { r = 9 }
  }
  return r
}
