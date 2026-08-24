## e2e — Grammar §4: comparisons are non-associative, but a PARENTHESIZED pair of comparisons
## joined by another comparison is well-formed and MUST NOT be false-rejected by the
## non-associativity guard. Each inner `<`/`>` is consumed inside its own parenthesized primary,
## so only the single top-level `==` reaches the comparison level.
##   (a < b) == (c > d) = (1 < 2) == (4 > 3) = true == true = true → 42.
main := fn() -> u64 {
  a : u64 = 1
  b : u64 = 2
  c : u64 = 4
  d : u64 = 3
  if (a < b) == (c > d) { 42 } else { 0 }
}
