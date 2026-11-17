four := fn() -> u64 { 4 }
main := fn() -> u64 { util::len(four()) + util::pick(2) + util::first(util::S(a = 3, b = 4)) + 33 }
## Compiled alone (the corpus walk), this file names a module `util` it does not have.
## expect: reject
