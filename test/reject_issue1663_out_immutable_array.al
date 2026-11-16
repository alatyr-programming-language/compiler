## e2e reject — #1663: an immutable fixed-array local bound to an `in out` array parameter. Memory §3.1
## and Functions §2.3, as for a scalar; the callee's `xs[1] = 30` writes the caller's array. Distinct
## from #1632, which refused a write THROUGH an `in` array parameter: here the parameter is `out` /
## `in out` and it is the ARGUMENT that is immutable. MEASURED on the parent (`836b97ba`, native
## x86_64): `check` rc 0, x86_64 ran 42.
## expect: reject "check: immutable binding" "at line 10"
put := fn(in out xs : [u64; 3]) { xs[1] = 30 }
main := fn() -> u8 {
  v : [u64; 3] = [2, 0, 10]
  put(v)
  u8(v[1] + 12)
}
