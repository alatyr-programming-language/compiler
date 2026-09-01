## e2e — §4.3.3 caps the LINE, not the construct. The parameter list below closes at column 98 and
## so stays single-line by its own measurement; the result type that follows it on the same line
## carries the line to 105, and the list's width verdict never saw it. `fmt` now counts that pending
## result type into the verdict, so the list wraps one parameter per line, with the canonical
## trailing comma and the `)` back at the opening indent. The eight arguments are distinct powers
## of two and their sum is checked, so a wrap that dropped, duplicated or reordered one cannot
## reach 42; a disagreement returns 100.
sum_of_eight_scalars := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64) -> u64 {
  return a + b + c + d + e + f + g + h
}

main := fn() -> u64 {
  s := sum_of_eight_scalars(1, 2, 4, 8, 16, 32, 64, 128)
  if s != 255 { return 100 }
  return 42
}
