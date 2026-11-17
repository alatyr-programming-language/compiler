## The root's own `f`, with the bare name `b`'s function has too.
f := fn() -> u64 { 10 }
one := fn() -> u64 { b::f() + f() }
main := fn() -> u64 { one() }
## Compiled alone (the corpus walk), this file names a module `b` it does not have.
## expect: reject
