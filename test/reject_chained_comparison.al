## e2e build_reject — Grammar §4: comparison operators are NON-ASSOCIATIVE. A chained comparison
## `a < b < c` is ill-formed and MUST be rejected at the Parse stage (the parser panics; build rc
## != 0). Previously the parser folded it left-associatively as `(a < b) < c` and SILENTLY accepted
## it (comparing a bool with an integer) — a correctness defect. The build must now fail loud.
main := fn() -> u64 {
  a : u64 = 1
  b : u64 = 2
  c : u64 = 3
  if a < b < c { 42 } else { 0 }
}
