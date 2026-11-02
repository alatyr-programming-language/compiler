## e2e — issue #703 residual: a STORE through a field of an `i16` local.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, build 0, exit 3: the
## store landed nowhere.
main := fn() -> u64 {
  mut x : i16 = 3
  x.a = 4
  u64(x)
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_field_subword_store"
