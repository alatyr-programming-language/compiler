## Control Flow §5.4 — OR-patterns `p | q | r => body`: the arm matches when ANY alternative does
## (pure surface sugar, expanded to one arm per alternative). a = 40 (2 matches `1 | 2 | 3`),
## b = 2 (9 matches none → `_`) → 42.
main := fn() -> u64 {
  a := match 2 { 1 | 2 | 3 => 40 ; _ => 0 }
  b := match 9 { 1 | 2 | 3 => 99 ; _ => 2 }
  return a + b
}
