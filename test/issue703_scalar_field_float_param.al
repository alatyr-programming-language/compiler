## e2e — issue #703 residual: the owner is a PARAMETER declared `f64`.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, build 0, exit 7.
g := fn(p : f64) -> u64 {
  if p.zz == 0.0 { return 7 }
  1
}
main := fn() -> u64 { g(2.5) }
## expect: reject "a scalar has no field to name at line 4 in issue703_scalar_field_float_param"
