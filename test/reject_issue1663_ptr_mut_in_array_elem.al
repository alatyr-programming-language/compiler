## e2e reject — #1663: `ptr(mut xs[1])` over an `in` array parameter. The root binding `xs` is immutable
## (Memory §3.1, #1632's `prov_array_param_in`), so the AND-path to its element is not writable and
## §4.4 permits only `ptr(T)`. MEASURED on the parent (`836b97ba`, native x86_64): `check` rc 0,
## x86_64 ran 42.
## expect: reject "check: immutable binding" "at line 7"
poke := fn(xs : [u64; 3]) -> u64 {
  p := ptr(mut xs[1])
  deref(p) = 30
  xs[0]
}
main := fn() -> u8 {
  mut a : [u64; 3] = [2, 0, 10]
  r := poke(a)
  u8(a[1] + r + 12)
}
