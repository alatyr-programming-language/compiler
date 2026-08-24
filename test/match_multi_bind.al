## Regression (`check` parity): a `match` with MULTIPLE variant arms that each bind a payload
## variable. The statement-match checker pushes each arm's payload binds as ARM-SCOPED locals, then
## pops them (via `lvec_truncate`, keeping the local count in lockstep) so the next arm's push reuses
## the slot — else a later arm's binding lands beyond the visible count and reads as UNBOUND, wrongly
## rejecting a valid program. Exercises three binding arms (`First(x)`/`Second(y)`/`Third(z)`), an
## expression-match with a payload bind (`ev := match … { Some(w) => w … }`), and the runtime result.
Tri := enum { First(u64), Second(u64), Third(u64) }
Opt := enum { Some(u64), None }
mk := fn(sel : u64, v : u64) -> Tri {
  if sel == 0 { return Tri.First(v) }
  if sel == 1 { return Tri.Second(v) }
  return Tri.Third(v)
}
main := fn() -> u64 {
  t := mk(2, 6)
  a := match t {
    First(x) => { x }
    Second(y) => { y }
    Third(z) => { z + 30 }
  }                                  ## 6 + 30 = 36
  e := Opt.Some(6)
  ev := match e { Some(w) => w, None => 0 }   ## 6 — expression-match payload bind
  a + ev                             ## 36 + 6 = 42
}
