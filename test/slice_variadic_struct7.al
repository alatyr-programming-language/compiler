## Functions §7.2: a SLICE variadic with a STRUCT element `xs : ...Pt` gathering >6 (here SEVEN, an ODD
## count) trailing struct args into one contiguous runtime `[Pt]` data block — exercises the lifted
## `ng > 6` cap on the AGGREGATE gather path. psum(Pt(3,3) x7) = 7 * (3 + 3) = 42.
Pt := struct { a : u64, b : u64 }
psum := fn(xs : ...Pt) -> u64 {
  mut s : u64 = 0
  for p in xs {
    s = s + p.a + p.b
  }
  return s
}
main := fn() -> u64 {
  return psum(Pt(a = 3, b = 3), Pt(a = 3, b = 3), Pt(a = 3, b = 3), Pt(a = 3, b = 3), Pt(a = 3, b = 3), Pt(a = 3, b = 3), Pt(a = 3, b = 3))
}
