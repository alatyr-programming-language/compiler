## #714 residual: a GENERIC fn whose DECLARED return is a concrete wide struct (not its type parameter)
## delivers through the hidden pointer like any other wide-SRET call. aarch64's generic-call branch never
## loaded x8 for it, so both the discarded call and the BOUND one (`d := mk(u64, 1)`) wrote through a
## stale x8 (SIGSEGV, 139). The `-> T` form is `sret_discard_generic`, a separate shape.
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

mk := fn(T : type, n : T) -> S9 {
  return S9(a = n, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
}

main := fn() -> u64 {
  mk(u64, 1)
  d := mk(u64, 1)
  return d.h + 34
}
