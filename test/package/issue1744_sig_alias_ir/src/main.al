## The root's own `Inner`, three words with `a` and `b` at other offsets, and its own `Word`.
Inner := struct { z : u64, b : u64, a : u64 }
Word := u64
use := fn() -> u64 { m::sum(m::mk()) }
boxed := fn() -> u64 { m::unbox(m::mkbox()) }
payload := fn() -> u64 { m::une(m::mke()) }
main := fn() -> u64 { use() + boxed() + payload() - 16 }
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
