main := fn() -> u64 { a::get() + z::other() }
## Compiled alone (the corpus walk), this file names modules `a` and `z` it does not have.
## expect: reject
