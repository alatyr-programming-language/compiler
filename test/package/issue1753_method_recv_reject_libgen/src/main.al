W := m::W
get := fn(x : u64) -> u64 { return x + 1 }
main := fn() -> u64 {
  v := alloc::vec::new(u64)
  w := W(v = 42)
  return w.get()
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
