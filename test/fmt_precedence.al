## fmt — bitwise / comparison PRECEDENCE round-trips (§5 tooling). fmt re-inserts the grouping parens
## the parser erased ONLY where the re-parse would otherwise re-group, and DROPS redundant ones:
##   `(a | b) & c` keeps its parens (`|` binds LOOSER than `&`, so a bare `a | b & c` = `a | (b & c)`),
##   `(a & b) | c` DROPS them (`&` already binds tighter, `a & b | c` re-parses identically),
##   `(a < c) == (b < c)` keeps them (a comparison operand of a comparison is non-associative).
## a=8, b=3, c=10:  r=(8|3)&10=10, s=(8&3)|10=10, t=(8^3)&10=10 → 30; (8<10)==(3<10) → true → +12 = 42.
main := fn() -> u64 {
  a := 8
  b := 3
  c := 10
  r := (a | b) & c
  s := (a & b) | c
  t := (a ^ b) & c
  mut acc := r + s + t
  if (a < c) == (b < c) { acc = acc + 12 }
  return acc
}
