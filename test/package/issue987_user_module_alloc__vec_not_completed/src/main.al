main := fn() -> u64 { alloc__vec::run() }
## Compiled alone (the corpus walk), this file names a module `alloc__vec` it does not have.
## expect: reject
