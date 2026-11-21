(mix) := m
main := fn() -> u64 {
  mix(42)
  return 42
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
