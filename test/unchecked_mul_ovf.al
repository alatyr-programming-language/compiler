## Companion: `unchecked` drops the `*` overflow guard → 6148914691236517206 * 3 wraps to 2 (mod 2^64). run_a64 → 2.
main := fn() -> u64 {
  a := 6148914691236517206
  b := unchecked { a * 3 }
  return b
}
