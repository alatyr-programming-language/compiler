## The root package's entry module. It does NOT touch the declared dependency — the point of the
## fixture is that merely DECLARING one leaves this module's `main` (and its `main__main` symbol)
## exactly where it was.
main := fn() -> u64 {
  return 42
}
