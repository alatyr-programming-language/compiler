## e2e accept — #1663's control: every LEGAL place argument stays legal and its write is visible to the
## caller. A `mut` local bound to `in out`, and that same parameter re-passed as `out` / `in out`
## (the caller's place, Functions §2.1), and a whole `mut` array bound to an `in out` array parameter
## (Memory §3.1: the binding is `mut`, so §2.3 admits it). 2+10=12, +10=22; a[2] 0+10=10 → 22+10+12=44.
## expect: run 44
put := fn(in out x : u64) { x = x + 10 }
io := fn(in out z : u64) { put(z) }
putarr := fn(in out xs : [u64; 3]) { xs[2] = xs[2] + 10 }
main := fn() -> u8 {
  mut v : u64 = 2
  put(v)
  io(v)
  mut a : [u64; 3] = [1, 0, 0]
  putarr(a)
  u8(v + a[2] + 12)
}
