## e2e reject — #1663: an `in` parameter handed on as an `in out` argument. Functions §9's `in-param`
## grammar admits no `mut`, so `x` is an immutable binding (Memory §3.1) and §2.3 refuses it as a place
## argument. MEASURED on the base (`1b3b22e0`, native x86_64): `check` rc 0, built and executed 14 —
## the write reached `io`'s copy and not the caller's `v`, but the program is ill-formed either way.
## expect: reject "check: immutable binding" "at line 7"
put := fn(in out y : u64) { y = 30 }
io := fn(x : u64) { put(x) }
main := fn() -> u8 {
  mut v : u64 = 2
  io(v)
  u8(v + 12)
}
