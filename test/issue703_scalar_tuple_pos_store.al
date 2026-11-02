## e2e — issue #703 residual: a STORE to a tuple position `.0` of a `u64` local.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, while build stopped in
## the lower with a non-located internal message.
main := fn() -> u64 {
  mut x : u64 = 3
  x.0 = 4
  x
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_tuple_pos_store"
