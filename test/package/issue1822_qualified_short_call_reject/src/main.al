main := fn() -> u64 {
  return m::mix(42)
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
