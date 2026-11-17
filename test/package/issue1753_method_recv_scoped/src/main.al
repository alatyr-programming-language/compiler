get := fn(x : u64) -> u64 { return x + 1 }
main := fn() -> u64 {
  x : u64 = 1
  return x.get() + m::probe()
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
