## The root's own `S` and `T`, each another layout than the struct `m` and `k` mean.
S := struct { p : u64, q : u64, r : u64 }
T := struct { q : u64 }

main := fn() -> u64 {
  s := S(p = 4, q = 6, r = 0)
  t := T(q = 0)
  return s.p + s.q + s.r + t.q + m::viat() + k::viak()
}
## Compiled alone (the corpus walk), this file names a module it does not have.
## expect: reject
