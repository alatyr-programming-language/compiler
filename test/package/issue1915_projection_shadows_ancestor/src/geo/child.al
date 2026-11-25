(f, g) := other
pub run := fn() -> u64 { f(40) + g(41) }
## Compiled alone (the corpus walk), this file names a module `other` it does not have.
## expect: reject
