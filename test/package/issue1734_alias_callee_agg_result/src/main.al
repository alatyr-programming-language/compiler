mk := m::mk
weigh := m::weigh
## The caller's own `S`: a different declaration of the same name, `a` at another offset.
S := struct { z : u64, a : u64, b : u64 }

main := fn() -> u64 {
  v := mk()
  w := S(z = 0, a = 7, b = 9)
  return v.a + v.b + weigh(v) + mk().a + w.z
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
