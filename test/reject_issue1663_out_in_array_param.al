## e2e reject — #1663: an `in` array parameter handed on as an `in out` argument. #1632 gave the `in`
## array its own immutable provenance (`prov_array_param_in`) and refused a WRITE through it; this is
## the other half — the parameter itself passed as a place argument, which §2.3 refuses because the
## binding is immutable (Memory §3.1). MEASURED on the parent (`836b97ba`, native x86_64): `check` rc 0.
## expect: reject "check: immutable binding" "at line 8"
put := fn(in out xs : [u64; 3]) { xs[1] = 30 }
go := fn(xs : [u64; 3]) -> u64 {
  put(xs)
  xs[0]
}
main := fn() -> u8 {
  mut a : [u64; 3] = [2, 0, 10]
  r := go(a)
  u8(r + 12)
}
