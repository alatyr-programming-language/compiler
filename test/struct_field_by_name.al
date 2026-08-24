## TYP-8 — struct construction is BY NAME, not by source position. Regression for a silent
## miscompile: `P(y = 6, x = 5)` used to drop the field names and store values POSITIONALLY, so `y`'s
## value (6) landed in field 0 (`x`) — any out-of-declaration-order literal silently produced wrong
## values (violating TYP-8 and I11). The parser now REORDERS each named field to its declaration index,
## so both orders below produce x=5, y=6 regardless of how they are written. Returns 42.
P := struct { x : u64, y : u64 }

## Wider struct exercising a 3-way permutation and interleaved values (c=3,a=1,b=2 -> declaration a,b,c).
Q := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  ## out-of-order: the bug case. y is written first but must reach the `y` slot.
  p1 := P(y = 6, x = 5)
  if p1.x != 5 { return 1 }             ## y=6 must NOT have shifted into x
  if p1.y != 6 { return 2 }
  if p1.x * 10 + p1.y != 56 { return 3 } ## the headline check: 56, never 65

  ## declaration order: must stay correct (was correct only by coincidence before).
  p2 := P(x = 5, y = 6)
  if p2.x * 10 + p2.y != 56 { return 4 }

  ## full 3-way reversal + interleave.
  q := Q(c = 3, a = 1, b = 2)
  if q.a != 1 { return 5 }
  if q.b != 2 { return 6 }
  if q.c != 3 { return 7 }
  if q.a * 100 + q.b * 10 + q.c != 123 { return 8 }

  return 42
}
