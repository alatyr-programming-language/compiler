## FN-6 cross-backend seam: a non-capturing lambda bound to a local name is called directly.
## The driver lifts the lambda to a synthetic function declaration; every backend must resolve
## the FnRef binding instead of treating the code pointer as an unsupported value.
main := fn() -> u64 {
  lam := fn(n : u64) -> u64 { return n + 4 }
  return lam(6)
}
