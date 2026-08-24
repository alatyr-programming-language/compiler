## e2e — CONCURRENCY builtins (spec ch.110): the prelude `atomic`/`volatile` operation modules +
## `fence`, on a `ptr(mut T)`, each taking a comptime `Ordering`. Lowered to x86_64 atomic instructions
## (xchgq / lock xaddq / mfence / plain movq for volatile). Single-threaded here, so this checks the
## SEQUENTIAL semantics + that every op + ordering lowers:
##   swap(p,50)  -> old 100, x=50 ;  fetch_sub(p,8) -> old 50, x=42 ;  load -> 42 ;
##   volatile store 15 then load -> 15.  z(42) + a(100) + b(50) + c(15) - 165 = 42.
main := fn() -> u64 {
  mut x := 100
  p := ptr(x)
  a := atomic::swap(p, 50, Ordering.seq_cst)
  b := atomic::fetch_sub(p, 8, Ordering.acq_rel)
  fence(Ordering.seq_cst)
  mut y := 0
  q := ptr(y)
  volatile::store(q, 15, Ordering.relaxed)
  c := volatile::load(q, Ordering.relaxed)
  z := atomic::load(p, Ordering.acquire)
  z + a + b + c - 165
}
