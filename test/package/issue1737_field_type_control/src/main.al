## No `Inner` here: `P`'s field types can only come from `wide`.
Other := struct { x : u64, y : u64, z : u64 }

main := fn() -> u64 {
  w := Other(x = 0, y = 0, z = 0)
  return wide::mk().v + w.x
}
## Compiled alone (the corpus walk), this file names a module `wide` it does not have.
## expect: reject
