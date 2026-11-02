pub get := fn() -> u64 {
  z::n.x = 4
  z::n
}
## Compiled alone (the corpus walk), this file names a module `z` it does not have.
## expect: reject
