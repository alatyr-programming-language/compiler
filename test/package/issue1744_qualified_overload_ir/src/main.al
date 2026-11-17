wide := fn(x : u64) -> u64 { m::pick(x) }
main := fn() -> u64 { wide(40) + m::narrow() }
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
