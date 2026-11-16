## e2e reject — #1663: a FIELD of an immutable struct local bound to an `in out` parameter. Memory §3.3's
## AND rule: the write permission of a path is the AND of every step, and the root step `s` fails it;
## §4.4's `ptr(mut c.f)` clause states the same requirement for the address route. The store
## `s.a = 30` in the callee writes the caller's field. MEASURED on the parent (`836b97ba`, native
## x86_64): `check` rc 0, x86_64 ran 42.
## expect: reject "check: immutable binding" "at line 11"
S := struct { mut a : u64, b : u64 }
put := fn(in out x : u64) { x = 30 }
main := fn() -> u8 {
  s := S(a = 2, b = 10)
  put(s.a)
  u8(s.a + 12)
}
