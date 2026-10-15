## #909, the array form: `xs = [xs[1] + 3, xs[0], xs[2]]` assigns the VALUE of the literal, (4, 0, 0).
## Built in place on x86_64, element 1 read the element 0 the literal had just written (44); the
## shared IR builds the literal in its own frame object and copies it (40).
main := fn() -> u64 {
  mut xs : [u64; 3] = [0, 1, 0]
  xs = [xs[1] + 3, xs[0], xs[2]]
  xs[0] * 10 + xs[1]
}
