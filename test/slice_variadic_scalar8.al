## Functions §7.2: a HOMOGENEOUS SLICE variadic `xs : ...u64` gathering >6 (here EIGHT) trailing scalar
## args into one runtime `[u64]` slice — exercises the lifted `ng > 6` cap on the scalar gather path.
## sum(2,4,6,8,10,7,3,2) = 42.
sum := fn(xs : ...u64) -> u64 {
  mut s : u64 = 0
  for x in xs {
    s = s + x
  }
  return s
}
main := fn() -> u64 {
  return sum(2, 4, 6, 8, 10, 7, 3, 2)
}
