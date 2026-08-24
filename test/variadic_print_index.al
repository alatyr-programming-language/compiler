## Wave 6 / TOOL-5: a comptime-variadic print hole must use the RESULT TYPE of
## an indexed expression, not the source spelling of that expression. The same
## type must survive a call whose argument is indexed, and a pre-bound local is
## the control case for the existing Var path.
f := fn(x : u64) -> u64 {
  return x + 1
}

main := fn() -> u64 {
  xs : [u64; 2] = [40, 1]
  std::fmt::print("{}\n", xs[0])
  std::fmt::print("{}\n", f(xs[1]))
  x := xs[0]
  std::fmt::print("{}\n", x)
  42
}
