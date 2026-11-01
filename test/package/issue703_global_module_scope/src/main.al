## The package answers 42: a::get() is 5 + 7, z::other() is 3 + 4, plus 23.
main := fn() -> u64 { a::get() + z::other() + 23 }
## Compiled alone (the corpus walk), this file names modules `a` and `z` it does not have.
## expect: reject
