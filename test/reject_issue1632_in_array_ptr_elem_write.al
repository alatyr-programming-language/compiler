## e2e reject — #1632: an element write through an `in` array parameter whose ELEMENT type is a pointer.
## The parameter's recorded type is its element's, and the checker's type-based answer lets a pointer
## typed root through (a pointer's own permission is a separate contract), so the refusal must come from
## the parameter's direction, not its element type (sema `prov_array_param_in`). Memory §3.1/§3.4: the
## binding `xs` is immutable; storing a new pointer into its element writes `xs`, not a pointee.
## MEASURED on the parent (`774ba852`, native x86_64): `check` passed.
## expect: reject "check: immutable binding" "at line 9"
put := fn(xs : [ptr(u64); 2], p : ptr(u64)) -> u64 {
  xs[0] = p
  deref(xs[0])
}
main := fn() -> u8 {
  a : u64 = 40
  b : u64 = 2
  q := put([ptr(a), ptr(b)], ptr(b))
  u8(q + 40)
}
