## e2e — issue #703 residual: the owner is an UNANNOTATED module global bound to an integer literal.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, build 0, exit 7.
G := 5
main := fn() -> u64 {
  if G.a == 0 { return 7 }
  1
}
## expect: reject "a scalar has no field to name at line 5 in issue703_scalar_field_global_unannotated"
