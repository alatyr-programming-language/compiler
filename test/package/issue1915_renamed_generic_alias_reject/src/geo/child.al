f := other::h
pub run := fn() -> u64 { f(u64, 40) }
## Compiled alone (the corpus walk), this file names a module `other` it does not have.
## expect: reject
