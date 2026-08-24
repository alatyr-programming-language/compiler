## A comptime-constant element write initializes exactly that fixed-array element.
main := fn() -> u64 {
  mut xs : [u64; 2]
  xs[0] = 42
  return xs[0]
}
