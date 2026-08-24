## e2e — Grammar §4 operator precedence: the three bitwise operators occupy DISTINCT tiers,
## tightest→loosest `&` (level 5) > `^` (level 6) > `|` (level 7), all left-associative. So an
## unparenthesized `a | b & c` MUST group as `a | (b & c)`, NOT `(a | b) & c`. Values chosen so
## the two groupings give DIFFERENT results — this locks the fix:
##   spec  a | (b & c) = 40 | (2 & 2) = 40 | 2 = 42   (correct)
##   defect (a | b) & c = (40 | 2) & 2 = 42 & 2 = 2   (the old collapsed single-tier grouping)
## The program returns the computed value; a green e2e (exit 42) proves the spec grouping.
main := fn() -> u64 {
  a : u64 = 40
  b : u64 = 2
  c : u64 = 2
  a | b & c
}
