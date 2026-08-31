## e2e (P3, compound assignment): `+=` on scalars and struct fields.
## Both are desugared in the parser to Assign/FieldAssign with a Bin(+, lhs, rhs) value.
## Expected exit: 42.
Counter := struct { n : usize }
main := fn() -> u64 {
  mut x : usize = 0
  x += 10
  x += 5
  mut c := Counter(n = 0)
  c.n += 27
  return u64(x + c.n)
}
