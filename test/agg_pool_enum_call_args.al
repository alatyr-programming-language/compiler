## e2e (#772, #801 — Functions §4 ABI: every aggregate-value temporary argument gets its own block).
## A call whose arguments hold an ENUM-RETURNING call beside a second unnamed aggregate temporary —
## another enum-returning call, an enum or struct constructor, a struct-returning call — is a valid
## program. x86_64 refused every one of these shapes: the pool of temporary blocks was sized by a scan
## that never counted an enum-returning call argument, the emission took one block more than the scan
## reserved, and the build aborted. The smallest such call is `gee(mk0(), mk0())` below; progen's first
## nightly run hit this class in 34 of 4000 seeds.
## Every argument is read and each position is weighted differently (`gee` = a + 3e), so two arguments
## handed the same block would change the sum. Values:
##   r0 = gee(B(2,3), B(2,3))    = 8 + 24 = 32
##   r1 = gee(A(1), A(2))        = 1 + 6  = 7
##   r2 = gee(B(1,2), A(3))      = 5 + 9  = 14
##   r3 = gee(A(4), B(1,1))      = 4 + 9  = 13
##   r4 = gse(S(2), A(1))        = 2 + 3  = 5
##   r5 = gse(mks(3), A(2))      = 3 + 6  = 9
##   r6 = 11 when #772's own shape `g(mk(5), g(E.A(1), 2))` = 5 + (1 + 2) = 8 holds as an `if` condition
##   t  = g(mk(5), g(E.A(1), 2)) = 8, as a binding's initializer
## main = 32 + 7 + 14 + 13 + 5 + 9 + 11 + 8 = 99 (below 126 for WASI's `proc_exit`).
## Parent `1c5c73b`: the build aborted on the pool-overflow refusal (rc 1), no binary.
E := enum { A(u64), B(u64, u64) }
S := struct { k1 : u64 }

mk0 := fn() -> E { return E.B(2, 3) }
mke := fn(v : u64) -> E { return E.A(v) }
mks := fn(v : u64) -> S { return S(k1 = v) }

## The value an `E` carries: A(x) is x, B(x, y) is x + 2y.
ev := fn(e : E) -> u64 {
  match e {
    E::A(x) => { return x }
    E::B(x, y) => { return x + 2 * y }
  }
}

gee := fn(a : E, e : E) -> u64 { return ev(a) + 3 * ev(e) }
gse := fn(s : S, e : E) -> u64 { return s.k1 + 3 * ev(e) }
g := fn(e : E, x : u64) -> u64 { return ev(e) + x }

main := fn() -> u64 {
  r0 := gee(mk0(), mk0())
  r1 := gee(mke(1), mke(2))
  r2 := gee(E.B(1, 2), mke(3))
  r3 := gee(mke(4), E.B(1, 1))
  r4 := gse(S(k1 = 2), mke(1))
  r5 := gse(mks(3), mke(2))
  mut r6 : u64 = 0
  if g(mke(5), g(E.A(1), 2)) == 8 { r6 = 11 }
  t : u64 = g(mke(5), g(E.A(1), 2))
  return r0 + r1 + r2 + r3 + r4 + r5 + r6 + t
}
