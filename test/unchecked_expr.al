## Verification-mode scope smoke (Types §4.2): `unchecked <expr>` lowers transparently on every
## backend — the wrapped arithmetic still computes its value. (Checked-default guards land in a
## later slice; here the observable behavior is just that the wrapper is value-transparent.)
main := fn() -> u64 {
  a : u64 = 40
  b : u64 = 2
  s := unchecked (a + b)
  return s
}
