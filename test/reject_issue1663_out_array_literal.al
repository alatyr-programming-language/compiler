## e2e reject — #1663: an array LITERAL bound to an `in out` array parameter. Functions §2.3: a non-place
## argument is ill-formed; there is no place whose elements the callee could write in place, so the
## literal's words were dropped on the floor. Located at the callee. MEASURED on the parent
## (`836b97ba`, native x86_64): `check` rc 0.
## expect: reject "check: immutable binding" "at line 8"
put := fn(in out xs : [u64; 3]) { xs[1] = 30 }
main := fn() -> u8 {
  put([2, 0, 10])
  u8(7)
}
