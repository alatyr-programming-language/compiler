## e2e — issue #703 residual: the owner is an UNANNOTATED local bound to a call that returns `u64`.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, build 0, exit 7.
h := fn() -> u64 { 9 }
main := fn() -> u64 {
  x := h()
  if x.a == 0 { return 7 }
  1
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_field_unannotated_call"
