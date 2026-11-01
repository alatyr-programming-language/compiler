main := fn() -> u64 { a::get() + 34 }
## Compiled alone (the corpus walk), this file names a module `a` it does not have.
## expect: reject
