## A fixed-array literal is an N-element aggregate (Types §9.4); no lattice class relates it to a
## word-sized integer sink.
main := fn() -> u64 {
  x : u64 = [1, 2]
  return x
}
