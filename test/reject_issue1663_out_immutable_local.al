## e2e reject — #1663: an immutable local bound to an `in out` parameter. Functions §2.3: "A place
## argument (for out / in out) MUST be a mutable place (Memory §3) of the matching type"; Memory §3.1:
## a binding is immutable unless declared `mut`; §3.4: checked always. The direct store `v = 30` was
## already refused with this diagnostic — the call route reached the same place unchecked, and the callee
## wrote through it. MEASURED on the parent (`836b97ba`, native x86_64): `check` rc 0, x86_64 ran 42.
## expect: reject "check: immutable binding" "at line 10"
put := fn(in out x : u64) { x = 30 }
main := fn() -> u8 {
  v : u64 = 2
  put(v)
  u8(v + 12)
}
