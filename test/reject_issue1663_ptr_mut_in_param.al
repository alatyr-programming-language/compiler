## e2e reject — #1663: `ptr(mut x)` over an `in` PARAMETER. Functions §9's `in-param` admits no `mut`,
## so `x` is an immutable binding (Memory §3.1) and §4.4 gives it only `ptr(T)`; the caller's local was
## written through the pointer the callee took. MEASURED on the parent (`836b97ba`, native x86_64):
## `check` rc 0, x86_64 ran 42.
## expect: reject "check: immutable binding" "at line 7"
poke := fn(x : u64) {
  p := ptr(mut x)
  deref(p) = 30
}
main := fn() -> u8 {
  mut v : u64 = 2
  poke(v)
  u8(v + 12)
}
