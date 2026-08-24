## The mirror: §3.4's "a literal takes its type from context" fixes the numeric TYPE a literal takes,
## never that it becomes an aggregate.
main := fn() -> u64 {
  x : [u64; 2] = 7
  return 0
}
