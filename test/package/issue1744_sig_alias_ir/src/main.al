## The root's own `Inner`, three words with `a` and `b` at other offsets.
Inner := struct { z : u64, b : u64, a : u64 }
use := fn() -> u64 {
  t := m::mk()
  t.a + t.b
}
main := fn() -> u64 { use() }
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
