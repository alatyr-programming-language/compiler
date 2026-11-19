S := struct { a : u64, b : u64 }
mk := fn() -> S { S(a = 3, b = 4) }
main := fn() -> u64 { util::pick(mk()) + 38 }
## Compiled alone (the corpus walk), this file names a module `util` it does not have.
## expect: reject
