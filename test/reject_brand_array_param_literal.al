## Issue #698 / Types §4.2, §5.4 — an ARRAY parameter `xs : [A; 2]` fed an array literal of a SIBLING
## brand `B`. The parser records the parameter by its element type, so the brand judge compared `A`
## against the whole literal, named no identity, and let it through: the parent built this and ran it
## to 32 — `B(2)` and `B(3)` read out of slots declared `A`. Refused now, at the argument.
A := brand(u64)
B := brand(u64)
take := fn(xs : [A; 2]) -> u64 { return u64(xs[0]) + u64(xs[1]) * 10 }
main := fn() -> u64 {
  b : B = B(2)
  c : B = B(3)
  return take([b, c])
}
