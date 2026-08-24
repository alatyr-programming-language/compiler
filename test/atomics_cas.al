## e2e — atomic COMPARE-AND-SWAP (spec ch.110 §2): cas_strong / cas_weak on a ptr(mut T), each taking
## a success + a failure Ordering and returning `(current : T, succeeded : bool)` — bound as a 2-word
## tuple (`.0` current, `.1` succeeded), lowered to a single `lock cmpxchgq`. x starts 40:
##   r = cas_strong(expect 40 -> 41): matches, x=41, r=(40, 1)
##   s = cas_weak(expect 40 -> 99):   x is 41 now, FAILS, x stays 41, s=(41, 0)
##   t = cas_strong(expect 41 -> 42): matches, x=42, t=(41, 1)
## z (load) = 42. Returns z + r.1 + s.1 - t.1 = 42 + 1 + 0 - 1 = 42.
main := fn() -> u64 {
  mut x := 40
  p := ptr(x)
  r := atomic::cas_strong(p, 40, 41, Ordering.seq_cst, Ordering.acquire)
  s := atomic::cas_weak(p, 40, 99, Ordering.seq_cst, Ordering.relaxed)
  t := atomic::cas_strong(p, 41, 42, Ordering.seq_cst, Ordering.acquire)
  z := atomic::load(p, Ordering.acquire)
  z + r.1 + s.1 - t.1
}
