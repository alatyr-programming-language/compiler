## e2e reject — #1663: an element of an IMMUTABLE fixed array bound to an `out` / `in out` parameter.
## Functions §2.3's place-argument rule with Memory §3.1 and §3.3: the path `a[0]` has no mutable step,
## because the root binding `a` is immutable and an index step adds no permission of its own, so the
## AND fails at the root. `sema_place_root_var` recurses through `Index`, so this is the fence's own
## judgement and not a side effect of the scalar case. The direct store `a[0] = 30` was already refused
## with this diagnostic; the call route reached the same place unchecked. Emission of a place argument
## that IS an array element is separately defective (#1684), which is why this stays a reject row and
## never a `run` row — `check` refuses it before any code is emitted.
## expect: reject "check: immutable binding" "at line 13"
put := fn(in out x : u64) { x = 30 }
main := fn() -> u8 {
  a : [u64; 3] = [2, 0, 10]
  put(a[0])
  u8(a[0] + 12)
}
