f := other::f
pub run := fn() -> u64 { f(40) }
## Compiled alone (the corpus walk), this file names a module `other` it does not have.
## expect: reject
