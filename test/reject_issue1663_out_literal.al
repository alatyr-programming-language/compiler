## e2e reject — #1663: a LITERAL bound to an `out` parameter. Functions §2.3 names the case: "Passing a
## non-place (e.g. a literal) to an out / in out … is ill-formed." There is no place for the callee to
## write into, so the result of `put` was simply lost. Located at the callee, since a literal names no
## place of its own. MEASURED on the parent (`836b97ba`, native x86_64): `check` rc 0.
## expect: reject "check: immutable binding" "at line 8"
put := fn(out x : u64) { x = 30 }
main := fn() -> u8 {
  put(42)
  u8(7)
}
