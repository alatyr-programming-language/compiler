W := z::W
main := fn() -> u64 {
  w := W(v = 42)
  return w.get()
}
get := fn(x : u64) -> u64 { return x + 1 }
## Compiled alone (the corpus walk), this file names a module `z` it does not have.
## expect: reject
