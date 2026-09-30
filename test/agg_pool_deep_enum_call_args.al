## e2e (#772, #801 — Functions §4 ABI): aggregate-value temporaries nested five calls deep. While a
## call's later argument is being evaluated, the blocks of its earlier aggregate arguments are still
## live, so a nested call's blocks stack above them; here enum-returning calls, an enum constructor and
## a struct-returning call sit at every level, next to a scalar argument that is itself such a call.
## x86_64 sized its pool of blocks with a scan that did not count an enum-returning call argument, so
## the emission ran past the reservation and the build aborted; the pool is now sized by the emission.
## Each position is weighted differently, so a block shared by two live arguments changes the answer:
##   h3(a, b, c) = ev(a) + 2 ev(b) + 4 ev(c);  hs(s, e, x) = s.k1 + 2 s.k2 + 3 ev(e) + x
##   h3(A(0), A(1), A(0))               = 2
##   hs(S(1, 0), A(0), 2)               = 1 + 0 + 0 + 2   = 3
##   mkb(0, 3)                          -> ev = 0 + 6     = 6
##   h3(A(1), A(0), B(0, 3))            = 1 + 0 + 24      = 25
##   h3(A(1), B(1, 0), A(25))           = 1 + 2 + 100     = 103
## Parent `1c5c73b`: the build aborted on the pool-overflow refusal (rc 1), no binary.
E := enum { A(u64), B(u64, u64) }
S := struct { k1 : u64, k2 : u64 }

mke := fn(v : u64) -> E { return E.A(v) }
mkb := fn(x : u64, y : u64) -> E { return E.B(x, y) }
mks := fn(a : u64, b : u64) -> S { return S(k1 = a, k2 = b) }

## The value an `E` carries: A(x) is x, B(x, y) is x + 2y.
ev := fn(e : E) -> u64 {
  match e {
    E::A(x) => { return x }
    E::B(x, y) => { return x + 2 * y }
  }
}

h3 := fn(a : E, b : E, c : E) -> u64 { return ev(a) + 2 * ev(b) + 4 * ev(c) }
hs := fn(s : S, e : E, x : u64) -> u64 { return s.k1 + 2 * s.k2 + 3 * ev(e) + x }

main := fn() -> u64 {
  return h3(mke(1), E.B(1, 0), mke(h3(mke(1), mke(0), mkb(0, hs(mks(1, 0), mke(0), h3(mke(0), mke(1), mke(0)))))))
}
