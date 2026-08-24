## Companion: `unchecked` drops the `-` underflow guard → 0 - 214 wraps to 2^64-214, low byte 42. run_a64 → 42.
main := fn() -> u64 {
  a := 0
  b := unchecked { a - 214 }
  return b
}
