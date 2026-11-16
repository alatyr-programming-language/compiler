## e2e reject — #1663: an `in` parameter handed on as an `in out` argument. Functions §9's `in-param`
## grammar admits no `mut`, so `x` is an immutable binding (Memory §3.1) and §2.3 refuses it as a place
## argument; the callee's write lands in the caller's local. MEASURED on the parent (`836b97ba`, native
## x86_64): `check` rc 0, x86_64 ran 42.
## expect: reject "check: immutable binding" "at line 7"
put := fn(in out y : u64) { y = 30 }
io := fn(x : u64) { put(x) }
main := fn() -> u8 {
  mut v : u64 = 2
  io(v)
  u8(v + 12)
}
