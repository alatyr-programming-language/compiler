## e2e — §4.2.3, the 100-column rule, for the one construct whose overflow its own sub-construct
## cannot see: a value-`if` written inline. Its condition's width verdict is taken before the braced
## arms exist, so a condition that measures 96 columns yields a 116-column LINE and the margin is
## missed by exactly the width of the arms. The condition here is a five-term `and` chain: §4.2.3's
## second bullet gives that a wrapped spelling (break before each operator, one level in), and it is
## the only construct on the line the spec names one for. Both truth values are exercised, so a wrap
## that dropped or re-grouped a term cannot reach 42; the first disagreement returns 100 or 101.
verdict := fn(alpha_counter : u64, bravo_counter : u64, charlie_counter : u64) -> u64 {
  if alpha_counter == 1 and bravo_counter == 1 and charlie_counter == 1 and alpha_counter != 9 { 42 } else { 1 }
}

main := fn() -> u64 {
  if verdict(1, 1, 1) != 42 { return 100 }
  if verdict(1, 1, 2) != 1 { return 101 }
  return 42
}
