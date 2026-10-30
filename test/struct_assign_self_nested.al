## #909, a piecewise literal as the FIRST initializer: the array literal `[p.xs[1], p.xs[0]]` is itself
## stored element by element, so built in place its element 1 read the element 0 it had just written.
## Right: xs = (2, 1), z = 21 -> 2 * 10 + 1 + 21 = 42; in place: xs = (2, 2) -> 43.
P := struct { xs : [u64; 2], z : u64 }
main := fn() -> u64 {
  mut p := P(xs = [1, 2], z = 3)
  p = P(xs = [p.xs[1], p.xs[0]], z = 21)
  p.xs[0] * 10 + p.xs[1] + p.z
}
## expect: run 42
